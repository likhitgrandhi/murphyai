import SwiftUI

// Item in the @-autocomplete dropdown. Humans are visual-only at MVP — no
// notification or backend behavior is wired yet, but they appear in the
// suggestion list so message text can include their handle.
private enum MentionResult: Identifiable {
    case agent(TeamAgent)
    case human(WorkspaceMember)

    var id: String {
        switch self {
        case .agent(let a): return "a:\(a.id.uuidString)"
        case .human(let m): return "h:\(m.userId.uuidString)"
        }
    }
}

struct SharedChannelView: View {
    let channel: ServerChannel

    @Environment(SharedChannelStore.self) private var store
    @Environment(AgentRoster.self) private var roster
    @Environment(AgentStore.self) private var agentStore
    @Environment(SessionStore.self) private var session

    @State private var inputText = ""
    @State private var sending = false
    @State private var sendError: String?
    @State private var showAddAgent = false

    // @-autocomplete
    @State private var mentionQuery: String? = nil   // non-nil while @-typing

    private var messages: [ServerMessage] {
        store.messagesByChannel[channel.id] ?? []
    }

    private var typingEntries: [TypingEntry] {
        store.typingByChannel[channel.id] ?? []
    }

    private var autocompleteResults: [MentionResult] {
        guard let q = mentionQuery else { return [] }
        let lowerQ = q.lowercased()

        let agents = roster.agents(in: channel.id)
        let agentMatches: [MentionResult] = agents
            .filter { lowerQ.isEmpty
                || $0.slug.lowercased().hasPrefix(lowerQ)
                || $0.displayName.lowercased().hasPrefix(lowerQ) }
            .map { .agent($0) }

        // Workspace humans the caller can see, excluding self.
        let me = session.currentUser?.id
        let humans = store.membersById.values
            .filter { $0.userId != me }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        let humanMatches: [MentionResult] = humans
            .filter { lowerQ.isEmpty
                || mentionHandle(for: $0).hasPrefix(lowerQ)
                || $0.name.lowercased().hasPrefix(lowerQ) }
            .map { .human($0) }

        return agentMatches + humanMatches
    }

    private func mentionHandle(for member: WorkspaceMember) -> String {
        // Use the local-part of the email as the @-handle (no usernames yet).
        if let at = member.email.firstIndex(of: "@") {
            return String(member.email[..<at]).lowercased()
        }
        return member.email.lowercased()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Kin.border).frame(height: 1)
            messageArea
            if !typingEntries.isEmpty { typingBar }
            inputArea
        }
        .background(Kin.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAddAgent) {
            AddAgentToChannelSheet(channel: channel, onAdded: {
                Task { await roster.refreshChannelAgents(for: channel.id) }
            })
            .environment(roster)
            .environment(agentStore)
        }
        .task {
            store.markViewed(channel.id)
            await store.fetchHistory(channelId: channel.id)
            store.markRead(channel.id)
            await roster.refreshChannelAgents(for: channel.id)
        }
        .onDisappear {
            if store.viewedChannelId == channel.id {
                store.viewedChannelId = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: channel.isDM ? "at" : "number")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Kin.textTertiary)
                Text(channel.displayName)
                    .font(Kin.inter(16, weight: .bold))
                    .foregroundStyle(Kin.textPrimary)
            }
            if let topic = channel.topic, !topic.isEmpty {
                Rectangle()
                    .fill(Kin.textTertiary.opacity(0.4))
                    .frame(width: 1, height: 20)
                Text(topic)
                    .font(Kin.inter(14, weight: .medium))
                    .foregroundStyle(Kin.textQuaternary)
                    .lineLimit(1)
            }
            Spacer()
            if !channel.isDM {
                Button { showAddAgent = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                        Text("Add agent")
                            .font(Kin.inter(11, weight: .medium))
                    }
                    .foregroundStyle(Kin.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Kin.inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Messages

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if messages.isEmpty {
                        emptyState.padding(.top, 60)
                    } else {
                        ForEach(messages) { msg in
                            MessageRow(
                                message: msg,
                                displayName: displayName(for: msg),
                                isYou: msg.senderKind == .user && msg.senderUserId == session.currentUser?.id,
                                isAgent: msg.senderKind == .agent
                            )
                            .id(msg.id)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
            }
            .onChange(of: messages.last?.id) { _, newId in
                guard let id = newId else { return }
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    private func displayName(for msg: ServerMessage) -> String {
        switch msg.senderKind {
        case .agent:
            return msg.agentDisplayName ?? msg.agentSlug ?? "Agent"
        case .user:
            return store.displayName(for: msg.senderUserId ?? UUID(), currentUserId: session.currentUser?.id)
        case .system:
            return "System"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No messages yet")
                .font(Kin.inter(13, weight: .semibold))
                .foregroundStyle(Kin.textSecondary)
            Text(channel.isDM
                 ? "Say hello to \(channel.displayName)."
                 : "Start the conversation in #\(channel.displayName).")
                .font(Kin.inter(12))
                .foregroundStyle(Kin.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Typing indicator

    private var typingBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: -4) {
                ForEach(Array(typingEntries.prefix(3).enumerated()), id: \.offset) { idx, _ in
                    Circle()
                        .fill(Kin.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: CGFloat(idx) * -2)
                }
            }
            let names = typingEntries.map(\.agentDisplayName)
            Text(typingLabel(names))
                .font(Kin.inter(11))
                .foregroundStyle(Kin.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 5)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func typingLabel(_ names: [String]) -> String {
        switch names.count {
        case 1: return "\(names[0]) is replying…"
        case 2: return "\(names[0]) and \(names[1]) are replying…"
        default: return "\(names[0]) and \(names.count - 1) others are replying…"
        }
    }

    // MARK: - Input

    private var inputArea: some View {
        VStack(spacing: 0) {
            // @-autocomplete popover above the input
            if !autocompleteResults.isEmpty {
                mentionAutocomplete
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            if let err = sendError {
                Text(err)
                    .font(Kin.inter(11))
                    .foregroundStyle(Kin.statusOffline)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Message \(channel.isDM ? channel.displayName : "#\(channel.displayName)")",
                          text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Kin.inter(13))
                    .foregroundStyle(Kin.textPrimary)
                    .lineLimit(1...8)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Kin.inputBg)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Kin.border, lineWidth: 1))
                    .onSubmit { send() }
                    .onChange(of: inputText) { _, new in updateMentionQuery(new) }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(canSend ? Kin.accent : Kin.textQuaternary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private var mentionAutocomplete: some View {
        let visible = Array(autocompleteResults.prefix(6))
        return VStack(spacing: 0) {
            ForEach(Array(visible.enumerated()), id: \.element.id) { idx, item in
                Button { completeMention(item) } label: {
                    HStack(spacing: 8) {
                        mentionAvatar(item)
                        Text("@\(handle(for: item))")
                            .font(Kin.inter(12, weight: .semibold))
                            .foregroundStyle(Kin.textPrimary)
                        Text(displayName(for: item))
                            .font(Kin.inter(11))
                            .foregroundStyle(Kin.textTertiary)
                        Spacer()
                        if case .agent = item {
                            Text("Agent")
                                .font(Kin.inter(9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.purple.opacity(0.7))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if idx != visible.count - 1 {
                    Divider().background(Kin.border)
                }
            }
        }
        .background(Kin.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Kin.border, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func mentionAvatar(_ item: MentionResult) -> some View {
        switch item {
        case .agent(let a):
            ZStack {
                Circle()
                    .fill((Color(hex: a.avatarTint ?? "") ?? Kin.accent).opacity(0.18))
                    .frame(width: 24, height: 24)
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: a.avatarTint ?? "") ?? Kin.accent)
            }
        case .human(let m):
            ZStack {
                Circle().fill(Kin.accent.opacity(0.18)).frame(width: 24, height: 24)
                Text(m.initials)
                    .font(Kin.inter(9, weight: .bold))
                    .foregroundStyle(Kin.accent)
            }
        }
    }

    private func handle(for item: MentionResult) -> String {
        switch item {
        case .agent(let a): return a.slug
        case .human(let m): return mentionHandle(for: m)
        }
    }

    private func displayName(for item: MentionResult) -> String {
        switch item {
        case .agent(let a): return a.displayName
        case .human(let m): return m.name
        }
    }

    private func updateMentionQuery(_ text: String) {
        // Find the last @word at the cursor position (simplified: find last @)
        if let atRange = text.range(of: "@", options: .backwards) {
            let afterAt = text[atRange.upperBound...]
            // Only trigger if there's no space after the @
            if !afterAt.contains(" ") && !afterAt.contains("\n") {
                mentionQuery = String(afterAt)
                return
            }
        }
        mentionQuery = nil
    }

    private func completeMention(_ item: MentionResult) {
        let token: String
        switch item {
        case .agent(let a): token = a.slug
        case .human(let m): token = mentionHandle(for: m)
        }
        if let atRange = inputText.range(of: "@", options: .backwards) {
            inputText = inputText[inputText.startIndex..<atRange.lowerBound] + "@\(token) "
        }
        mentionQuery = nil
    }

    private var canSend: Bool {
        !sending && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        sendError = nil
        Task {
            defer { sending = false }
            do {
                _ = try await store.sendUserMessage(text, in: channel)
                inputText = ""
            } catch {
                sendError = error.localizedDescription
            }
        }
    }
}

// MARK: - Message row

private struct MessageRow: View {
    let message: ServerMessage
    let displayName: String
    let isYou: Bool
    let isAgent: Bool

    @State private var thinkingExpanded = false

    private var accentColor: Color {
        isAgent ? .purple : Kin.accent
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(Kin.inter(13, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    if isAgent {
                        Text("Agent")
                            .font(Kin.inter(9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textTertiary)
                }
                if let thinking = message.thinking, !thinking.isEmpty {
                    SharedThinkingRow(text: thinking, expanded: $thinkingExpanded)
                }
                Text(message.content ?? "")
                    .font(Kin.inter(13))
                    .foregroundStyle(Kin.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                // Tool cards (redacted summaries only)
                if let cards = message.toolCards, !cards.isEmpty {
                    toolCardList(cards)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(accentColor.opacity(isYou ? 0.22 : 0.14))
                .frame(width: 32, height: 32)
            if isAgent {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentColor)
            } else {
                Text(initials)
                    .font(Kin.inter(11, weight: .bold))
                    .foregroundStyle(accentColor)
            }
        }
    }

    private func toolCardList(_ cards: [ServerMessage.ToolCard]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(cards.enumerated()), id: \.offset) { _, card in
                HStack(spacing: 6) {
                    Image(systemName: card.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(card.ok ? Kin.statusOnline : Kin.statusOffline)
                    Text(card.name)
                        .font(Kin.inter(10, weight: .semibold))
                        .foregroundStyle(Kin.textSecondary)
                    Text(card.summary)
                        .font(Kin.inter(10))
                        .foregroundStyle(Kin.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Kin.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}

// MARK: - Thinking row

private struct SharedThinkingRow: View {
    let text: String
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Kin.textSecondary)
                    Image(systemName: "brain")
                        .font(.system(size: 9))
                        .foregroundStyle(Kin.textSecondary)
                    Text("Thought")
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textSecondary)
                }
            }
            .buttonStyle(.plain)
            if expanded {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle().fill(Kin.accent.opacity(0.4)).frame(width: 2)
                    Text(verbatim: text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Kin.textSecondary)
                        .textSelection(.enabled)
                        .padding(.leading, 8)
                }
                .padding(.leading, 14)
                .transition(.opacity)
            }
        }
    }
}
