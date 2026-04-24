import SwiftUI

// MARK: - Channel thread view

struct ChannelView: View {
    let channel: Channel
    let runner: ChannelRunner

    @Environment(AgentStore.self) var store
    @State private var inputText = ""
    @State private var showSettings = false
    @State private var mentionQuery = ""
    @State private var showMentionPicker = false

    private var memberAgents: [AgentConfig] {
        store.agents.filter { channel.memberAgentIds.contains($0.id) }
    }

    private var mentionCandidates: [AgentConfig] {
        guard showMentionPicker else { return [] }
        if mentionQuery.isEmpty { return memberAgents }
        return memberAgents.filter { $0.name.lowercased().hasPrefix(mentionQuery.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            channelHeader
            Rectangle().fill(Kin.border).frame(height: 1)
            messageArea
            inputArea
        }
        .background(Kin.bg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSettings) {
            ChannelSettingsModal(channel: channel, runner: runner, isPresented: $showSettings)
                .environment(store)
        }
    }

    // MARK: - Header

    private var channelHeader: some View {
        HStack(spacing: 0) {
            // LEFT — # + name + divider + topic
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    Text("#")
                        .font(Kin.inter(20, weight: .bold))
                        .foregroundStyle(Kin.textTertiary)
                    Text(channel.name)
                        .font(Kin.inter(16, weight: .bold))
                        .foregroundStyle(.white)
                }
                if !channel.topic.isEmpty {
                    Rectangle()
                        .fill(Kin.textTertiary.opacity(0.4))
                        .frame(width: 1, height: 20)
                    Text(channel.topic)
                        .font(Kin.inter(14, weight: .medium))
                        .foregroundStyle(Kin.textQuaternary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 7)

            Spacer()

            // RIGHT — member avatars + buttons + search bar
            HStack(spacing: 8) {
                // Overlapping member avatars (Figma: 32pt circles, -6.667pt overlap)
                if !memberAgents.isEmpty {
                    HStack(spacing: -6) {
                        ForEach(memberAgents.prefix(3)) { agent in
                            AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 32, avatarPath: agent.avatarPath)
                                .overlay(Circle().stroke(Kin.bg, lineWidth: 2))
                        }
                        if memberAgents.count > 3 {
                            ZStack {
                                Circle().fill(Kin.surface)
                                Text("+\(memberAgents.count - 3)")
                                    .font(Kin.inter(11, weight: .semibold))
                                    .foregroundStyle(Kin.textSecondary)
                            }
                            .frame(width: 32, height: 32)
                            .overlay(Circle().stroke(Kin.bg, lineWidth: 2))
                        }
                    }
                }

                HStack(spacing: 4) {
                    if !runner.messages.isEmpty {
                        Button { runner.clearHistory() } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Kin.textTertiary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
                        .help("Clear channel")
                    }
                    Button { showSettings.toggle() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(showSettings ? Kin.accent : Kin.textTertiary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PressScaleButtonStyle(scale: 0.88))
                    .help("Channel settings")
                }

                // Search bar — Figma: bg #17171a, border #303035, rounded-8
                HStack {
                    Text("Search")
                        .font(Kin.inter(14, weight: .medium))
                        .foregroundStyle(Kin.textTertiary)
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundStyle(Kin.textTertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .frame(width: 200)
                .background(Kin.chatSearchBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Kin.chatSearchBorder, lineWidth: 1))
            }
            .padding(.trailing, 12)
        }
        .frame(height: 55)
        .padding(.horizontal, 5)
        .background(Kin.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Kin.chatBorder).frame(height: 1)
        }
    }

    // MARK: - Message area

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let groups = groupMessages(runner.messages)
                    ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                        if idx == 0, let date = group.date {
                            ChannelDateDivider(date: date)
                        } else if idx > 0,
                           let prev = groups[idx-1].date, let cur = group.date,
                           !Calendar.current.isDate(prev, inSameDayAs: cur) {
                            ChannelDateDivider(date: cur)
                        }
                        ChannelMessageGroupView(group: group, agents: memberAgents)
                            .id(group.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)),
                                removal: .opacity
                            ))
                    }

                    // Pending indicator: agents that are active but haven't produced content yet.
                    // Renders as a single row with overlapping avatars so the list isn't cluttered
                    // by N empty placeholders while a wave is running.
                    let pending = pendingAgents
                    if !pending.isEmpty {
                        ChannelPendingRow(agents: pending)
                            .transition(.opacity)
                    }

                    if let err = runner.claudeError {
                        ChannelErrorRow(text: err) { runner.claudeError = nil }
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.top, 16).padding(.bottom, 8)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: runner.messages.count)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: runner.messages.count) { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: pendingAgents.count) { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    /// Agents that are running but whose message hasn't been appended yet (no content so far).
    private var pendingAgents: [AgentConfig] {
        let startedIds: Set<String> = Set(runner.messages.compactMap { msg -> String? in
            if case .agent(let id) = msg.sender, msg.isStreaming { return id }
            return nil
        })
        let pending = runner.activeAgentIds.subtracting(startedIds)
        return memberAgents.filter { pending.contains($0.id) }
    }

    // MARK: - Input area

    private var inputArea: some View {
        VStack(spacing: 0) {
            // @ mention picker
            if !mentionCandidates.isEmpty {
                MentionPickerView(agents: mentionCandidates) { agent in
                    insertMention(agent)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }

            // Input container: HStack with plus/stop + text field + send button
            HStack(spacing: 0) {
                // LEFT — plus / stop button
                Button {
                    if !runner.activeAgentIds.isEmpty { runner.stopAll() }
                } label: {
                    Image(systemName: !runner.activeAgentIds.isEmpty ? "xmark.circle.fill" : "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Kin.textTertiary)
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.9))

                // RIGHT — text field + send button
                HStack(spacing: 0) {
                    TextField("Message #\(channel.name)…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Kin.inter(16))
                        .foregroundStyle(Kin.textPrimary)
                        .lineLimit(1...8)
                        .onSubmit { sendMessage() }
                        .onChange(of: inputText) { _, new in updateMentionState(new) }

                    Button {
                        if !runner.activeAgentIds.isEmpty { runner.stopAll() } else { sendMessage() }
                    } label: {
                        Image(systemName: !runner.activeAgentIds.isEmpty ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(sendButtonFg)
                            .frame(width: 32, height: 32)
                            .background(sendFill, in: Circle())
                    }
                    .disabled(!canSend && runner.activeAgentIds.isEmpty)
                    .buttonStyle(PressScaleButtonStyle(scale: 0.88))
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: canSend)
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: runner.activeAgentIds.isEmpty)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .background(Kin.inputBg, in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .padding(.top, 12)
        .background(Kin.bg)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && runner.activeAgentIds.isEmpty
            && ClaudeRunner.isAvailable()
    }

    private var sendFill: Color {
        if !runner.activeAgentIds.isEmpty { return Kin.statusOffline }
        if canSend { return Kin.accent }
        return Color.clear
    }

    private var sendButtonFg: Color {
        (canSend || !runner.activeAgentIds.isEmpty) ? .white : Kin.textTertiary
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, runner.activeAgentIds.isEmpty else { return }
        inputText = ""
        showMentionPicker = false
        runner.send(userMessage: text, channel: channel, agents: store.agents, store: store)
    }

    private func updateMentionState(_ text: String) {
        let words = text.components(separatedBy: " ")
        if let last = words.last, last.hasPrefix("@") {
            mentionQuery = String(last.dropFirst())
            showMentionPicker = true
        } else {
            showMentionPicker = false
            mentionQuery = ""
        }
    }

    private func insertMention(_ agent: AgentConfig) {
        var words = inputText.components(separatedBy: " ")
        if words.last?.hasPrefix("@") == true { words.removeLast() }
        words.append("@\(agent.name) ")
        inputText = words.joined(separator: " ")
        showMentionPicker = false
        mentionQuery = ""
    }

    // MARK: - Message grouping

    private func groupMessages(_ msgs: [ChannelMessage]) -> [ChannelGroup] {
        var groups: [ChannelGroup] = []
        var cur: [ChannelMessage] = []
        for msg in msgs {
            if cur.last?.sender == msg.sender { cur.append(msg) }
            else {
                if !cur.isEmpty {
                    groups.append(ChannelGroup(id: cur[0].id, sender: cur[0].sender,
                                               messages: cur, date: cur[0].date))
                }
                cur = [msg]
            }
        }
        if !cur.isEmpty {
            groups.append(ChannelGroup(id: cur[0].id, sender: cur[0].sender,
                                       messages: cur, date: cur[0].date))
        }
        return groups
    }
}

// MARK: - Message group view

private struct ChannelMessageGroupView: View {
    let group: ChannelView.ChannelGroup
    let agents: [AgentConfig]

    private var agentForGroup: AgentConfig? {
        if case .agent(let id) = group.sender {
            return agents.first(where: { $0.id == id })
        }
        return nil
    }

    private var senderName: String {
        switch group.sender {
        case .user: return "You"
        case .agent(let id): return agents.first(where: { $0.id == id })?.name ?? id
        }
    }

    private var timestamp: String? {
        guard let date = group.date else { return nil }
        let fmt = DateFormatter(); fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // 32pt avatar
            if let agent = agentForGroup {
                AgentAvatarCircle(
                    name: agent.name, tint: agent.tint, size: 32,
                    avatarPath: agentForGroup?.avatarPath,
                    animated: group.messages.last?.isStreaming ?? false
                )
            } else {
                UserAvatarBubble()
            }

            VStack(alignment: .leading, spacing: 1) {
                // Sender header
                HStack(spacing: 8) {
                    Text(senderName)
                        .font(Kin.inter(14, weight: .medium))
                        .foregroundStyle(agentForGroup.map { Color(hex: $0.tint) ?? Kin.accent } ?? .white)
                    if let ts = timestamp {
                        Text(ts)
                            .font(Kin.inter(11))
                            .foregroundStyle(Kin.textTertiary)
                    }
                }

                ForEach(group.messages) { msg in
                    ChannelMessageContent(message: msg)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Message content

private struct ChannelMessageContent: View {
    let message: ChannelMessage
    @State private var toolsExpanded = false
    @State private var thinkingExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if case .user = message.sender {
                Text(verbatim: message.content)
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textPrimary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if !message.thinking.isEmpty {
                    ChannelThinkingRow(text: message.thinking, expanded: $thinkingExpanded)
                }
                if !message.toolCards.isEmpty {
                    ChannelToolCallsRow(cards: message.toolCards, expanded: $toolsExpanded)
                }
                if message.isStreaming && message.content.isEmpty
                    && message.thinking.isEmpty && message.toolCards.isEmpty {
                    ChannelDotsRow()
                } else if !message.content.isEmpty {
                    MarkdownText(message.content)
                }
            }
        }
        .padding(.bottom, 2)
    }
}

// MARK: - User avatar

private struct UserAvatarBubble: View {
    var body: some View {
        ZStack {
            Circle().fill(Kin.avatarBg)
            Text("Y").font(Kin.inter(14, weight: .semibold)).foregroundStyle(Kin.textTertiary)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Date divider

private struct ChannelDateDivider: View {
    let date: Date
    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let f = DateFormatter(); f.dateFormat = "d MMMM yyyy"; return f.string(from: date)
    }
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Kin.border).frame(height: 1)
            Text(label).font(Kin.inter(11, weight: .medium)).foregroundStyle(Kin.textSecondary).fixedSize()
            Rectangle().fill(Kin.border).frame(height: 1)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}

// MARK: - Typing row

private struct ChannelTypingRow: View {
    let agent: AgentConfig
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 32, avatarPath: agent.avatarPath, animated: true)
            ChannelDotsRow()
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .padding(.bottom, 0)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Streaming dots (inline, while content arrives)

private struct ChannelDotsRow: View {
    @State private var phase = false
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Kin.textSecondary).frame(width: 4, height: 4)
                    .opacity(phase ? 0.9 : 0.2)
                    .animation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(i) * 0.18), value: phase)
            }
        }
        .padding(.vertical, 10)
        .onAppear { phase = true }
    }
}

// MARK: - Tool calls row

private struct ChannelToolCallsRow: View {
    let cards: [ToolCard]; @Binding var expanded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { expanded.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .medium)).foregroundStyle(Kin.textSecondary)
                    Text("\(cards.count) tool call\(cards.count == 1 ? "" : "s")").font(Kin.inter(11)).foregroundStyle(Kin.textSecondary)
                }
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(cards) { c in
                        HStack(spacing: 5) {
                            Image(systemName: c.icon).font(.system(size: 9)).foregroundStyle(Kin.textTertiary)
                            Text(c.name).font(Kin.inter(11, weight: .medium)).foregroundStyle(Kin.textSecondary)
                            if !c.summary.isEmpty { Text(c.summary).font(.system(size: 11, design: .monospaced)).foregroundStyle(Kin.textTertiary).lineLimit(1) }
                        }.padding(.vertical, 1).padding(.leading, 14)
                    }
                }.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Thinking row

private struct ChannelThinkingRow: View {
    let text: String; @Binding var expanded: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button { withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { expanded.toggle() } } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .medium)).foregroundStyle(Kin.textSecondary)
                    Image(systemName: "brain").font(.system(size: 9)).foregroundStyle(Kin.textSecondary)
                    Text(text.isEmpty ? "Thinking…" : "Thought").font(Kin.inter(11)).foregroundStyle(Kin.textSecondary)
                }
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))
            if expanded && !text.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle().fill(Kin.accent.opacity(0.4)).frame(width: 2)
                    Text(verbatim: text).font(.system(size: 11, design: .monospaced)).foregroundStyle(Kin.textSecondary).textSelection(.enabled).padding(.leading, 8)
                }
                .padding(.leading, 14).transition(.opacity)
            }
        }
    }
}

// MARK: - Pending agents row (overlapping avatars + dots)

private struct ChannelPendingRow: View {
    let agents: [AgentConfig]

    private var label: String {
        if agents.count == 1 {
            return "\(agents[0].name) is working…"
        }
        return "\(agents.count) agents working…"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: -8) {
                ForEach(agents.prefix(4)) { agent in
                    AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 32, avatarPath: agent.avatarPath)
                        .overlay(Circle().stroke(Kin.bg, lineWidth: 2))
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(Kin.inter(12))
                    .foregroundStyle(Kin.textSecondary)
                ChannelDotsRow()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Error row

private struct ChannelErrorRow: View {
    let text: String; let onDismiss: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: text).font(Kin.inter(11)).foregroundStyle(Kin.textSecondary).textSelection(.enabled)
            Spacer()
            Button("dismiss") { onDismiss() }.font(Kin.inter(10)).foregroundStyle(Kin.textTertiary).buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 8).background(Kin.errorBg)
    }
}

// MARK: - @ Mention picker

private struct MentionPickerView: View {
    let agents: [AgentConfig]
    let onSelect: (AgentConfig) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(agents.prefix(5)) { agent in
                Button { onSelect(agent) } label: {
                    HStack(spacing: 8) {
                        AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 20, avatarPath: agent.avatarPath)
                        Text(agent.name).font(Kin.inter(12, weight: .medium)).foregroundStyle(Kin.textPrimary)
                        Text(agent.role).font(Kin.inter(11)).foregroundStyle(Kin.textSecondary).lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.98))
            }
        }
        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Kin.border, lineWidth: 1))
    }
}

// Expose ChannelGroup for ForEach
extension ChannelView {
    struct ChannelGroup: Identifiable {
        let id: UUID
        let sender: ChannelMessage.Sender
        let messages: [ChannelMessage]
        let date: Date?
    }
}
