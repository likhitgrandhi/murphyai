import Foundation
import Observation
import Supabase

// Orchestrates team-agent execution in shared channels.
// Lifecycle: bind() on workspace attach, reset() on workspace detach.
//
// Flow per @mention:
//   1. Realtime delivers a user message → SharedChannelStore calls onNewUserMessage
//   2. This runner parses @mentions against the channel's agent roster
//   3. For each match: claim_agent_run RPC (first claim wins)
//   4. Winner broadcasts typing indicator heartbeats every 2 s
//   5. ClaudeRunner runs the agent locally with channel-history context
//   6. On completion: post_agent_message RPC posts the redacted result
//   7. release_agent_run marks the lease done/failed
@Observable
@MainActor
final class SharedChannelRunner {
    // Local streaming state — the winning client sees tokens appear as the agent thinks.
    // Other clients see only the typing indicator + the final INSERT via realtime.
    private(set) var activeRuns: [UUID: ActiveRun] = [:]   // key = triggering message id

    private weak var storeRef: SharedChannelStore?
    private var rosterRef: AgentRoster?
    private var processedIds: Set<UUID> = []
    private var heartbeatTasks: [UUID: Task<Void, Never>] = [:]  // key = agent id

    struct ActiveRun {
        let channelId: UUID
        let agentSlug: String
        let agentDisplayName: String
        let runner: ClaudeRunner
        let startedAt: Date
    }

    // MARK: - Lifecycle

    func bind(store: SharedChannelStore, roster: AgentRoster) {
        storeRef = store
        rosterRef = roster
        store.onNewUserMessage = { [weak self] msg in
            Task { @MainActor [weak self] in await self?.handle(msg) }
        }
    }

    func reset() {
        storeRef?.onNewUserMessage = nil
        storeRef = nil
        rosterRef = nil
        for task in heartbeatTasks.values { task.cancel() }
        heartbeatTasks = [:]
        activeRuns = [:]
        processedIds = []
    }

    // MARK: - Message handling

    private func handle(_ msg: ServerMessage) async {
        guard msg.senderKind == .user,
              !processedIds.contains(msg.id),
              let content = msg.content,
              let roster = rosterRef else { return }

        processedIds.insert(msg.id)

        let channelAgents = roster.agents(in: msg.channelId)
        guard !channelAgents.isEmpty else { return }

        let mentioned = channelAgents.filter { agent in
            isMentioned(slug: agent.slug, in: content)
        }
        guard !mentioned.isEmpty else { return }

        for agent in mentioned {
            Task { @MainActor [weak self] in
                await self?.attempt(agent: agent, trigger: msg)
            }
        }
    }

    private func isMentioned(slug: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: slug)
        guard let re = try? NSRegularExpression(pattern: "@\(escaped)\\b", options: .caseInsensitive) else { return false }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Run lifecycle

    private func attempt(agent: TeamAgent, trigger: ServerMessage) async {
        guard let store = storeRef else { return }

        // Don't claim if we can't actually execute — let another channel member
        // with the Claude CLI installed win the race instead. Without this guard
        // a runner without `claude` would claim and silently post nothing.
        guard ClaudeRunner.isAvailable() else { return }

        // Race to claim the run
        struct ClaimResult: Decodable { let won: Bool }
        guard let result: ClaimResult = try? await kinSupabase
            .rpc("claim_agent_run", params: ClaimParams(messageId: trigger.id, agentId: agent.id))
            .execute()
            .value, result.won else { return }

        let channelId = trigger.channelId

        // Start typing heartbeat
        startHeartbeat(for: agent, in: channelId, store: store)

        // Build channel-history context (messages before the trigger, max 15)
        let history = recentHistory(for: channelId, before: trigger, in: store)

        // Ephemeral runner — no disk persistence for team-agent runs
        let runner = ClaudeRunner()
        runner.messages = history

        activeRuns[trigger.id] = ActiveRun(
            channelId: channelId,
            agentSlug: agent.slug,
            agentDisplayName: agent.displayName,
            runner: runner,
            startedAt: Date()
        )

        runner.send(
            userMessage: trigger.content ?? "",
            agent: agent.asAgentConfig(),
            memoryContent: ""
        )

        // Wait for Claude to finish (10 min hard cap)
        await waitForCompletion(of: runner, timeout: 600)

        // Tear down heartbeat and local state
        stopHeartbeat(for: agent.id)
        activeRuns.removeValue(forKey: trigger.id)
        await store.clearTypingBroadcast(channelId: channelId, agentSlug: agent.slug)

        let finalAssistant = runner.messages.last(where: { $0.role == .assistant })
        let content = finalAssistant?.content ?? ""
        let thinking = finalAssistant.flatMap { $0.thinking.isEmpty ? nil : $0.thinking }
        let toolCards: [RedactedToolCard]? = finalAssistant.flatMap {
            $0.toolCards.isEmpty ? nil : ToolCardRedactor.redact($0.toolCards)
        }
        let status = runner.claudeError == nil ? "done" : "failed"

        if !content.isEmpty {
            do {
                try await kinSupabase
                    .rpc("post_agent_message", params: PostParams(
                        channelId: channelId,
                        messageId: trigger.id,
                        agentId: agent.id,
                        agentSlug: agent.slug,
                        agentDisplayName: agent.displayName,
                        content: content,
                        thinking: thinking,
                        toolCards: toolCards
                    ))
                    .execute()
            } catch {
                print("[SharedChannelRunner] post_agent_message failed:", error)
            }
        }

        try? await kinSupabase
            .rpc("release_agent_run", params: ReleaseParams(
                messageId: trigger.id, agentId: agent.id, status: status
            ))
            .execute()
    }

    // MARK: - Helpers

    private func recentHistory(
        for channelId: UUID, before trigger: ServerMessage,
        in store: SharedChannelStore
    ) -> [ChatMessage] {
        (store.messagesByChannel[channelId] ?? [])
            .filter { $0.seq < trigger.seq && $0.senderKind != .system }
            .suffix(15)
            .compactMap { m -> ChatMessage? in
                guard let c = m.content, !c.isEmpty else { return nil }
                return ChatMessage(role: m.senderKind == .user ? .user : .assistant, content: c)
            }
    }

    private func waitForCompletion(of runner: ClaudeRunner, timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while runner.isStreaming && Date() < deadline {
            // Wait until isStreaming changes; use a nonisolated flag to safely bridge
            // the onChange closure (which fires on an arbitrary context) to the continuation.
            final class Flag: @unchecked Sendable {
                var fired = false
            }
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                let flag = Flag()
                withObservationTracking {
                    _ = runner.isStreaming
                } onChange: {
                    if !flag.fired { flag.fired = true; cont.resume() }
                }
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    if !flag.fired { flag.fired = true; cont.resume() }
                }
            }
        }
        if runner.isStreaming { runner.stop() }
    }

    private func startHeartbeat(for agent: TeamAgent, in channelId: UUID, store: SharedChannelStore) {
        heartbeatTasks[agent.id]?.cancel()
        heartbeatTasks[agent.id] = Task { [weak store] in
            while !Task.isCancelled {
                await store?.broadcastTyping(channelId: channelId,
                                             agentSlug: agent.slug,
                                             displayName: agent.displayName)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopHeartbeat(for agentId: UUID) {
        heartbeatTasks[agentId]?.cancel()
        heartbeatTasks.removeValue(forKey: agentId)
    }
}

// MARK: - RPC param types

private struct ClaimParams: Encodable {
    let messageId: UUID
    let agentId: UUID
    enum CodingKeys: String, CodingKey {
        case messageId = "p_message_id"
        case agentId   = "p_agent_id"
    }
}

private struct ReleaseParams: Encodable {
    let messageId: UUID
    let agentId: UUID
    let status: String
    enum CodingKeys: String, CodingKey {
        case messageId = "p_message_id"
        case agentId   = "p_agent_id"
        case status    = "p_status"
    }
}

private struct PostParams: Encodable {
    let channelId: UUID
    let messageId: UUID
    let agentId: UUID
    let agentSlug: String
    let agentDisplayName: String
    let content: String
    let thinking: String?
    let toolCards: [RedactedToolCard]?
    enum CodingKeys: String, CodingKey {
        case channelId        = "p_channel_id"
        case messageId        = "p_message_id"
        case agentId          = "p_agent_id"
        case agentSlug        = "p_agent_slug"
        case agentDisplayName = "p_agent_display_name"
        case content          = "p_content"
        case thinking         = "p_thinking"
        case toolCards        = "p_tool_cards"
    }
}
