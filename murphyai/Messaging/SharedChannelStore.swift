import AppKit
import Foundation
import Observation
import OSLog
import Supabase
import Realtime

// Realtime diagnostics. Visible in Console.app under subsystem "kin.app",
// category "RT". Filter the search field with `subsystem:kin.app` to see only
// these messages and skip the network-framework noise.
private let kinRT = Logger(subsystem: "kin.app", category: "RT")

// Entry in the per-channel typing indicator table.
// Expires after 5 s if no heartbeat arrives (watchdog in handleTypingBroadcast).
struct TypingEntry: Equatable, Sendable {
    let agentSlug: String
    let agentDisplayName: String
    var lastSeen: Date
}

@Observable
@MainActor
final class SharedChannelStore {
    // ─── Public observable state ─────────────────────────────────────────────
    var channels: [ServerChannel] = []
    var messagesByChannel: [UUID: [ServerMessage]] = [:]
    var membersById: [UUID: WorkspaceMember] = [:]
    var typingByChannel: [UUID: [TypingEntry]] = [:]
    var isLoading = false
    var error: String?

    // Tracks which channel the user is currently looking at, used for LRU eviction.
    var lastViewedAt: [UUID: Date] = [:]

    // Unread tracking: seq of the last message the user has read per channel.
    var lastReadSeqByChannel: [UUID: Int64] = [:]
    // Channel the user is actively viewing — suppresses sound and zeroes badge.
    var viewedChannelId: UUID?

    // SharedChannelRunner sets this to receive freshly-delivered user messages.
    // Only fires for realtime-delivered messages (not history fetches or our own sends).
    var onNewUserMessage: ((ServerMessage) -> Void)?

    // ─── Tunables (see plan §Cross-cutting concerns) ─────────────────────────
    private let maxMessagesPerChannel = 200
    private let maxCachedChannels     = 10
    private let realtimeTopicPrefix   = "kin-messages"

    // ─── Private state ───────────────────────────────────────────────────────
    private var notificationSound: NSSound?
    private var workspaceId: UUID?
    private var realtimeChannel: RealtimeChannelV2?
    private var workspaceEventsChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var workspaceEventsTask: Task<Void, Never>?
    private var broadcastSubscription: RealtimeSubscription?
    // High-water-mark seq per channel — used for keyset-paginated resync on
    // realtime reconnect (refetch only what we missed, not the whole history).
    private var lastSeqByChannel: [UUID: Int64] = [:]
    // Whether we've completed at least one successful subscribe pass — used to
    // distinguish the *first* `.subscribed` transition (no resync needed; we
    // fetched history fresh) from a *reconnect* (resync required).
    private var hasInitiallySubscribed = false

    // MARK: - Lifecycle

    func bind(workspaceId: UUID) async {
        // Idempotent: re-binding to the same workspace is a no-op so tearing
        // down a healthy subscription doesn't happen on every onAppear.
        if self.workspaceId == workspaceId { return }
        await teardown()
        self.workspaceId = workspaceId
        async let _refresh: () = refresh()
        async let _members: () = refreshMembers()
        _ = await (_refresh, _members)
        await subscribe()
    }

    func reset() async {
        await teardown()
        workspaceId = nil
        channels = []
        messagesByChannel = [:]
        membersById = [:]
        lastViewedAt = [:]
        lastReadSeqByChannel = [:]
        viewedChannelId = nil
        typingByChannel = [:]
        onNewUserMessage = nil
        error = nil
    }

    private func teardown() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        statusTask?.cancel()
        statusTask = nil
        workspaceEventsTask?.cancel()
        workspaceEventsTask = nil
        broadcastSubscription = nil
        hasInitiallySubscribed = false
        lastSeqByChannel = [:]
        if let ch = realtimeChannel {
            await ch.unsubscribe()
            await kinSupabase.realtimeV2.removeChannel(ch)
        }
        realtimeChannel = nil
        if let ch = workspaceEventsChannel {
            await ch.unsubscribe()
            await kinSupabase.realtimeV2.removeChannel(ch)
        }
        workspaceEventsChannel = nil
    }

    // MARK: - Channels

    func refresh() async {
        guard let wsId = workspaceId else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let rows: [ServerChannel] = try await kinSupabase
                .rpc("list_my_channels", params: ListChannelsParams(workspaceId: wsId))
                .execute()
                .value
            channels = rows
        } catch {
            self.error = error.localizedDescription
            print("[SharedChannelStore] list_my_channels failed:", error)
        }
    }

    func createChannel(name: String, topic: String?) async throws -> ServerChannel {
        guard let wsId = workspaceId else { throw MessagingError.notReady }
        let ch: ServerChannel = try await kinSupabase
            .rpc("create_channel", params: CreateChannelParams(
                workspaceId: wsId, name: name, topic: topic
            ))
            .execute()
            .value
        await refresh()
        return ch
    }

    private func refreshMembers() async {
        guard let wsId = workspaceId else { return }
        do {
            let members: [WorkspaceMember] = try await kinSupabase
                .rpc("list_workspace_members", params: ListMembersParamsLocal(workspaceId: wsId))
                .execute()
                .value
            membersById = Dictionary(uniqueKeysWithValues: members.map { ($0.userId, $0) })
        } catch {
            print("[SharedChannelStore] refreshMembers failed:", error)
        }
    }

    func displayName(for userId: UUID, currentUserId: UUID?) -> String {
        if userId == currentUserId { return "You" }
        if let m = membersById[userId] { return m.name }
        return "Unknown"
    }

    func openDM(with otherUserId: UUID) async throws -> ServerChannel {
        guard let wsId = workspaceId else { throw MessagingError.notReady }
        let ch: ServerChannel = try await kinSupabase
            .rpc("create_dm", params: CreateDMParams(
                workspaceId: wsId, otherUserId: otherUserId
            ))
            .execute()
            .value
        await refresh()
        return ch
    }

    // MARK: - Messages

    // Called by SharedChannelView.onAppear so we know what to keep hot in cache.
    func markViewed(_ channelId: UUID) {
        lastViewedAt[channelId] = Date()
        viewedChannelId = channelId
        evictLeastRecentlyViewedIfNeeded()
    }

    // Called after history is loaded to stamp the read horizon for this channel.
    func markRead(_ channelId: UUID) {
        let maxSeq = (messagesByChannel[channelId] ?? [])
            .filter { $0.seq != .max }
            .map(\.seq)
            .max() ?? 0
        lastReadSeqByChannel[channelId] = maxSeq
    }

    func unreadCount(for channelId: UUID) -> Int {
        if channelId == viewedChannelId { return 0 }
        let msgs = messagesByChannel[channelId] ?? []
        let readSeq = lastReadSeqByChannel[channelId] ?? 0
        return msgs.filter { $0.seq != .max && $0.seq > readSeq }.count
    }

    func fetchHistory(channelId: UUID, sinceSeq: Int64? = nil) async {
        do {
            var query = kinSupabase
                .from("messages")
                .select()
                .eq("channel_id", value: channelId)
            if let sinceSeq {
                // PostgrestFilterValue doesn't bridge Int64 directly; pass as Int.
                query = query.gt("seq", value: Int(sinceSeq))
            }
            let rows: [ServerMessage] = try await query
                .order("seq", ascending: true)
                .limit(maxMessagesPerChannel)
                .execute()
                .value
            mergeMessages(rows, into: channelId)
        } catch {
            self.error = error.localizedDescription
            print("[SharedChannelStore] fetchHistory failed:", error)
        }
    }

    // Optimistic send: append a local placeholder immediately so the user
    // sees their message land in the transcript without waiting on the round-trip,
    // then reconcile by id with the server's authoritative row (or roll back).
    @discardableResult
    func sendUserMessage(_ text: String, in channel: ServerChannel) async throws -> ServerMessage {
        guard let userId = kinSupabase.auth.currentUser?.id else {
            throw MessagingError.notAuthenticated
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw MessagingError.emptyMessage }

        // Optimistic placeholder. Negative seq sorts it after every server
        // message (we sort by seq ascending; placeholders use Int64.max so they
        // pin to the bottom until reconciled).
        let placeholderId = UUID()
        let placeholder = ServerMessage(
            id: placeholderId,
            channelId: channel.id,
            seq: .max,
            senderKind: .user,
            senderUserId: userId,
            agentId: nil,
            agentSlug: nil,
            agentDisplayName: nil,
            runByUserId: nil,
            content: trimmed,
            thinking: nil,
            toolCards: nil,
            createdAt: Date()
        )
        appendLocal(placeholder, into: channel.id)

        let payload = OutgoingUserMessage(
            channelId: channel.id,
            senderKind: "user",
            senderUserId: userId,
            content: trimmed
        )
        do {
            let inserted: ServerMessage = try await kinSupabase
                .from("messages")
                .insert(payload, returning: .representation)
                .select()
                .single()
                .execute()
                .value
            // Reconcile: drop the placeholder by id, merge the authoritative row.
            // The realtime stream will deliver the same row; mergeMessages dedupes.
            removeLocal(id: placeholderId, from: channel.id)
            mergeMessages([inserted], into: channel.id)
            return inserted
        } catch {
            // Roll back the optimistic state.
            removeLocal(id: placeholderId, from: channel.id)
            throw error
        }
    }

    private func appendLocal(_ msg: ServerMessage, into channelId: UUID) {
        var current = messagesByChannel[channelId] ?? []
        current.append(msg)
        current.sort()
        messagesByChannel[channelId] = current
    }

    private func removeLocal(id: UUID, from channelId: UUID) {
        guard var current = messagesByChannel[channelId] else { return }
        current.removeAll { $0.id == id }
        messagesByChannel[channelId] = current
    }

    // MARK: - Realtime

    private func subscribe() async {
        guard let wsId = workspaceId else { return }

        // Refresh the JWT on the realtime client. The SDK normally wires this
        // up via auth-state listeners; do it here too so RLS sees the right
        // user even if the listener hasn't fired yet.
        do {
            let token = try await kinSupabase.auth.session.accessToken
            await kinSupabase.realtimeV2.setAuth(token)
            kinRT.notice("realtime setAuth OK")
        } catch {
            kinRT.error("realtime setAuth failed: \(String(describing: error), privacy: .public)")
        }
        // No explicit connect() here — the SDK connects lazily on first
        // subscribe, and that suspension is what gives the binding-registration
        // Task time to run before the JOIN payload is built.

        // ── Channel 1: messages + typing broadcast ─────────────────────────
        // Slim by design: one postgres_changes binding + one broadcast.
        let topic = "\(realtimeTopicPrefix)-\(wsId.uuidString)"
        kinRT.notice("subscribe begin topic=\(topic, privacy: .public)")
        let ch = kinSupabase.realtimeV2.channel(topic)
        realtimeChannel = ch

        let insertStream = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "messages"
        )
        let statusStream = ch.statusChange

        broadcastSubscription = ch.onBroadcast(event: "typing") { [weak self] payload in
            Task { @MainActor [weak self] in self?.handleTypingBroadcast(payload) }
        }

        // CRITICAL: drain the @MainActor task queue so `postgresChange()`'s
        // binding-registration Task runs before subscribeWithError() is called.
        // Without this, _subscribe() reads `mutableState.clientChanges` while
        // the registration is still pending, JOIN goes out with empty bindings,
        // and the server never delivers events. Channel reaches `subscribed`
        // but nothing flows — exactly the bug we hit.
        await Task.yield()

        // ── Channel 2: workspace events (separate, best-effort) ───────────
        // If this subscription fails (e.g., migration 009 not applied), the
        // sidebar just won't live-update — messages still flow normally.
        let wsTopic = "kin-workspace-\(wsId.uuidString)"
        let wsCh = kinSupabase.realtimeV2.channel(wsTopic)
        workspaceEventsChannel = wsCh

        let channelsInsertStream = wsCh.postgresChange(
            InsertAction.self, schema: "public", table: "channels"
        )
        let channelMembersInsertStream = wsCh.postgresChange(
            InsertAction.self, schema: "public", table: "channel_members"
        )
        let membershipsInsertStream = wsCh.postgresChange(
            InsertAction.self, schema: "public", table: "memberships"
        )

        // Same race fix as the messages channel — drain the @MainActor queue
        // so binding registrations land in clientChanges before JOIN.
        await Task.yield()

        // Subscribe in a sibling Task; consumer loop runs independently so
        // events delivered after auto-reconnect (post initial timeout) still
        // reach us.
        Task {
            do {
                try await wsCh.subscribeWithError()
                kinRT.notice("workspace-events subscribed OK")
            } catch {
                kinRT.error("workspace-events subscribe initial failed: \(String(describing: error), privacy: .public) — listening for auto-reconnect")
            }
        }
        workspaceEventsTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await _ in channelsInsertStream {
                        if Task.isCancelled { break }
                        await self?.refresh()
                    }
                }
                group.addTask { [weak self] in
                    for await _ in channelMembersInsertStream {
                        if Task.isCancelled { break }
                        await self?.refresh()
                    }
                }
                group.addTask { [weak self] in
                    for await _ in membershipsInsertStream {
                        if Task.isCancelled { break }
                        await self?.refreshMembers()
                    }
                }
            }
        }

        // Status watcher — reconciles missed messages on reconnect.
        // The SDK auto-reconnects with backoff; we just observe transitions to
        // .subscribed and, if it's a re-subscribe (not the first), refetch.
        statusTask = Task { [weak self] in
            for await status in statusStream {
                if Task.isCancelled { break }
                guard let self else { break }
                kinRT.notice("status=\(String(describing: status), privacy: .public)")
                if status == .subscribed {
                    await MainActor.run {
                        if self.hasInitiallySubscribed {
                            // Reconnect path — refetch missed messages per channel,
                            // plus the channel list and member list (they may have
                            // changed while we were disconnected).
                            self.resyncAfterReconnect()
                            Task { await self.refresh() }
                            Task { await self.refreshMembers() }
                        } else {
                            self.hasInitiallySubscribed = true
                        }
                    }
                }
            }
        }

        // Subscribe runs in a sibling Task — its success/failure is independent
        // of the consumer loop below. The first attempt frequently times out
        // on a fresh socket (~60 s), but the SDK auto-reconnects internally
        // and the saved bindings get re-sent. By NOT returning from realtimeTask
        // on subscribe error, we keep iterating insertStream so those events
        // delivered after auto-reconnect actually reach our handler.
        Task {
            do {
                kinRT.notice("subscribeWithError…")
                try await ch.subscribeWithError()
                kinRT.notice("messages channel subscribed OK")
            } catch {
                kinRT.error("messages subscribe initial failed: \(String(describing: error), privacy: .public) — listening for auto-reconnect events")
            }
        }
        realtimeTask = Task { [weak self] in
            kinRT.notice("messages: waiting for events…")
            for await action in insertStream {
                if Task.isCancelled { break }
                guard let self else { break }
                kinRT.notice("messages INSERT received")
                do {
                    let msg = try action.decodeRecord(
                        as: ServerMessage.self,
                        decoder: .supabaseISO8601
                    )
                    await MainActor.run {
                        self.mergeMessages([msg], into: msg.channelId)
                        // Defensive: a message can arrive for a channel we don't
                        // know yet (e.g. someone just DM'd us and the channels
                        // realtime event hasn't been processed yet). Trigger a
                        // refresh so the sidebar catches up.
                        if !self.channels.contains(where: { $0.id == msg.channelId }) {
                            Task { await self.refresh() }
                        }
                        // Notify runner for freshly-arrived user messages only.
                        // Agent/system messages and history fetches don't trigger this.
                        if msg.senderKind == .user {
                            self.onNewUserMessage?(msg)
                        }
                        // Play notification sound for messages in non-active channels,
                        // ignoring messages the current user sent themselves.
                        let myId = kinSupabase.auth.currentUser?.id
                        let isMine = msg.senderKind == .user && msg.senderUserId == myId
                        if !isMine && msg.channelId != self.viewedChannelId {
                            self.playNotificationSound()
                        }
                    }
                } catch {
                    print("[SharedChannelStore] decode realtime insert failed:", error)
                }
            }
        }
    }

    private func resyncAfterReconnect() {
        // Refetch only the channels we have cached state for, using the
        // last-known seq as a high-water mark. New channels get backfilled
        // when the user opens them.
        let channelIds = Array(messagesByChannel.keys)
        for channelId in channelIds {
            let lastSeq = lastSeqByChannel[channelId]
            Task { [weak self] in
                await self?.fetchHistory(channelId: channelId, sinceSeq: lastSeq)
            }
        }
    }

    // MARK: - Buffer hygiene

    private func mergeMessages(_ incoming: [ServerMessage], into channelId: UUID) {
        guard !incoming.isEmpty else { return }
        var current = messagesByChannel[channelId] ?? []
        let known = Set(current.map(\.id))
        var maxSeenSeq = lastSeqByChannel[channelId] ?? 0
        for msg in incoming where !known.contains(msg.id) {
            current.append(msg)
            // Skip optimistic placeholders (seq == .max) when tracking high-water.
            if msg.seq != .max, msg.seq > maxSeenSeq { maxSeenSeq = msg.seq }
        }
        // Insertion-sort by seq is cheap; messages usually arrive in order.
        current.sort()
        // Bound the buffer.
        if current.count > maxMessagesPerChannel {
            current.removeFirst(current.count - maxMessagesPerChannel)
        }
        messagesByChannel[channelId] = current
        if maxSeenSeq > 0 {
            lastSeqByChannel[channelId] = maxSeenSeq
        }
    }

    private func evictLeastRecentlyViewedIfNeeded() {
        guard messagesByChannel.count > maxCachedChannels else { return }
        let candidates = messagesByChannel.keys.sorted { a, b in
            (lastViewedAt[a] ?? .distantPast) < (lastViewedAt[b] ?? .distantPast)
        }
        let evictCount = messagesByChannel.count - maxCachedChannels
        for id in candidates.prefix(evictCount) {
            messagesByChannel.removeValue(forKey: id)
        }
    }

    // MARK: - Notification sound

    private func playNotificationSound() {
        if notificationSound == nil,
           let url = Bundle.main.url(forResource: "notification", withExtension: "wav") {
            notificationSound = NSSound(contentsOf: url, byReference: false)
        }
        notificationSound?.stop()
        notificationSound?.play()
    }

    // MARK: - Typing broadcast

    func broadcastTyping(channelId: UUID, agentSlug: String, displayName: String) async {
        // Update local state too — Supabase Realtime doesn't echo broadcasts to
        // the sender by default, so without this the runner's own UI never sees
        // its own "Bob is replying…" indicator.
        var entries = typingByChannel[channelId] ?? []
        if let idx = entries.firstIndex(where: { $0.agentSlug == agentSlug }) {
            entries[idx].lastSeen = Date()
        } else {
            entries.append(TypingEntry(agentSlug: agentSlug, agentDisplayName: displayName, lastSeen: Date()))
        }
        typingByChannel[channelId] = entries

        guard let ch = realtimeChannel else { return }
        let payload = TypingPayload(channelId: channelId.uuidString, agentSlug: agentSlug,
                                    agentDisplayName: displayName, action: "heartbeat")
        try? await ch.broadcast(event: "typing", message: payload)
    }

    func clearTypingBroadcast(channelId: UUID, agentSlug: String) async {
        guard let ch = realtimeChannel else { return }
        let payload = TypingPayload(channelId: channelId.uuidString, agentSlug: agentSlug,
                                    agentDisplayName: "", action: "stop")
        try? await ch.broadcast(event: "typing", message: payload)
        removeTypingEntry(channelId: channelId, slug: agentSlug)
    }

    private func handleTypingBroadcast(_ payload: JSONObject) {
        guard let channelIdStr = payload["channel_id"]?.stringValue,
              let channelId = UUID(uuidString: channelIdStr),
              let slug = payload["agent_slug"]?.stringValue,
              let action = payload["action"]?.stringValue else { return }
        let displayName = payload["agent_display_name"]?.stringValue ?? slug

        switch action {
        case "heartbeat", "start":
            var entries = typingByChannel[channelId] ?? []
            if let idx = entries.firstIndex(where: { $0.agentSlug == slug }) {
                entries[idx].lastSeen = Date()
            } else {
                entries.append(TypingEntry(agentSlug: slug, agentDisplayName: displayName, lastSeen: Date()))
            }
            typingByChannel[channelId] = entries
        case "stop":
            removeTypingEntry(channelId: channelId, slug: slug)
        default:
            break
        }
        sweepStaleTypingEntries()
    }

    private func removeTypingEntry(channelId: UUID, slug: String) {
        typingByChannel[channelId]?.removeAll { $0.agentSlug == slug }
        if typingByChannel[channelId]?.isEmpty == true {
            typingByChannel.removeValue(forKey: channelId)
        }
    }

    private func sweepStaleTypingEntries() {
        let cutoff = Date().addingTimeInterval(-5)
        for (id, entries) in typingByChannel {
            let fresh = entries.filter { $0.lastSeen > cutoff }
            if fresh.isEmpty { typingByChannel.removeValue(forKey: id) }
            else { typingByChannel[id] = fresh }
        }
    }
}

// MARK: - Errors

enum MessagingError: LocalizedError {
    case notReady, notAuthenticated, emptyMessage
    var errorDescription: String? {
        switch self {
        case .notReady:         return "Workspace not ready."
        case .notAuthenticated: return "Sign in required."
        case .emptyMessage:     return "Message can't be empty."
        }
    }
}

// MARK: - RPC param / outgoing types

private struct ListChannelsParams: Encodable {
    let workspaceId: UUID
    enum CodingKeys: String, CodingKey { case workspaceId = "p_workspace_id" }
}

private struct CreateChannelParams: Encodable {
    let workspaceId: UUID
    let name: String
    let topic: String?
    enum CodingKeys: String, CodingKey {
        case workspaceId = "p_workspace_id"
        case name        = "p_name"
        case topic       = "p_topic"
    }
}

private struct CreateDMParams: Encodable {
    let workspaceId: UUID
    let otherUserId: UUID
    enum CodingKeys: String, CodingKey {
        case workspaceId = "p_workspace_id"
        case otherUserId = "p_other_user_id"
    }
}

private struct ListMembersParamsLocal: Encodable {
    let workspaceId: UUID
    enum CodingKeys: String, CodingKey { case workspaceId = "p_workspace_id" }
}

private struct TypingPayload: Codable {
    let channelId: String
    let agentSlug: String
    let agentDisplayName: String
    let action: String
    enum CodingKeys: String, CodingKey {
        case channelId         = "channel_id"
        case agentSlug         = "agent_slug"
        case agentDisplayName  = "agent_display_name"
        case action
    }
}

private struct OutgoingUserMessage: Encodable {
    let channelId: UUID
    let senderKind: String
    let senderUserId: UUID
    let content: String
    enum CodingKeys: String, CodingKey {
        case channelId    = "channel_id"
        case senderKind   = "sender_kind"
        case senderUserId = "sender_user_id"
        case content
    }
}

// MARK: - Decoder helper

extension JSONDecoder {
    // Supabase returns ISO 8601 with optional fractional seconds + Z.
    // The SDK's `.supabase()` factory isn't exposed publicly in our setup,
    // so we provide an equivalent that also tolerates "+00:00" offsets.
    static var supabaseISO8601: JSONDecoder {
        let d = JSONDecoder()
        let formatters: [ISO8601DateFormatter] = {
            let withFractional = ISO8601DateFormatter()
            withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            plain.formatOptions = [.withInternetDateTime]
            return [withFractional, plain]
        }()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            for f in formatters {
                if let date = f.date(from: raw) { return date }
            }
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unparseable ISO 8601 date: \(raw)"
            )
        }
        return d
    }
}
