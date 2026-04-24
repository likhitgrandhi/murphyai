import SwiftUI

// MARK: - Message grouping model

fileprivate struct MessageGroup: Identifiable {
    let id: UUID
    let role: ChatMessage.Role
    let messages: [ChatMessage]
    let date: Date?
}

// MARK: - Thread view

struct ThreadView: View {
    let agent: AgentConfig
    let runner: ClaudeRunner

    @Environment(AgentStore.self) var store
    @State private var inputText = ""
    @State private var showSettings = false
    @State private var showClearConfirm = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            VStack(spacing: 0) {
                threadHeader(at: ctx.date)
                messageArea(at: ctx.date)
                inputCard
            }
            .background(Kin.bg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showSettings) {
            AgentSettingsModal(agent: agent, isPresented: $showSettings)
                .environment(store)
        }
        .alert("Clear conversation?", isPresented: $showClearConfirm) {
            Button("Clear", role: .destructive) { runner.clearHistory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete all messages with \(agent.name).")
        }
    }

    // MARK: - Header

    private func threadHeader(at now: Date) -> some View {
        let status = runner.presenceStatus(at: now)
        return HStack(spacing: 0) {
            // LEFT — avatar + name + divider + role
            HStack(spacing: 14) {
                HStack(spacing: 6) {
                    AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 20, avatarPath: agent.avatarPath, status: status)
                    Text(agent.name)
                        .font(Kin.inter(16, weight: .bold))
                        .foregroundStyle(.white)
                }
                Rectangle()
                    .fill(Kin.textTertiary.opacity(0.4))
                    .frame(width: 1, height: 20)
                Text(agent.role)
                    .font(Kin.inter(14, weight: .medium))
                    .foregroundStyle(Kin.textQuaternary)
                    .lineLimit(1)
            }
            .padding(.leading, 7)

            Spacer()

            // RIGHT — action buttons + search bar
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    if !runner.messages.isEmpty {
                        Button { showClearConfirm = true } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(Kin.textTertiary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(PressScaleButtonStyle(scale: 0.88))
                        .help("Clear thread")
                    }
                    Button { showSettings.toggle() } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(showSettings ? Kin.accent : Kin.textTertiary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PressScaleButtonStyle(scale: 0.88))
                    .help("Settings")
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
        .frame(height: 48)
        .padding(.horizontal, 5)
        .background(Kin.bg)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Kin.chatBorder)
                .frame(height: 1)
        }
    }

    // MARK: - Message area

    private func messageArea(at now: Date) -> some View {
        let status = runner.presenceStatus(at: now)
        return ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 2) {
                    let groups = groupMessages(runner.messages)
                    ForEach(Array(groups.enumerated()), id: \.element.id) { idx, group in
                        if idx == 0, let date = group.date {
                            DateDividerRow(date: date)
                        } else if idx > 0,
                           let prevDate = groups[idx - 1].date,
                           let curDate = group.date,
                           !Calendar.current.isDate(prevDate, inSameDayAs: curDate) {
                            DateDividerRow(date: curDate)
                        }
                        MessageGroupView(
                            group: group,
                            agent: agent,
                            agentStatus: status,
                            isStreaming: runner.isStreaming && idx == groups.count - 1
                        )
                        .id(group.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)),
                                removal: .opacity
                            ))
                    }
                    if runner.isStreaming, runner.messages.last?.role == .user {
                        TypingGroupView(agent: agent, agentStatus: status)
                            .transition(.opacity)
                    }
                    if let err = runner.claudeError {
                        ErrorRow(text: err) { runner.claudeError = nil }
                            .transition(.opacity)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.top, 16)
                .padding(.bottom, 8)
                .animation(.spring(response: 0.38, dampingFraction: 0.82), value: runner.messages.count)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: runner.isStreaming)
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: runner.messages.last?.content) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: runner.messages.last?.toolCards.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: runner.messages.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }

    // MARK: - Input card

    private var inputCard: some View {
        VStack(spacing: 0) {
            // Input container: HStack with plus/xmark + text field + send button
            HStack(spacing: 0) {
                // LEFT — plus / stop button
                Button {
                    if runner.isStreaming { runner.stop() }
                    // else: attachment placeholder — no-op
                } label: {
                    Image(systemName: runner.isStreaming ? "xmark.circle.fill" : "plus")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Kin.textTertiary)
                        .frame(width: 44, height: 40)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.9))

                // RIGHT — text field + send button
                HStack(spacing: 0) {
                    TextField("Message \(agent.name)…", text: $inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(Kin.inter(16))
                        .foregroundStyle(Kin.textPrimary)
                        .lineLimit(1...8)
                        .onSubmit { sendMessage() }

                    // Send / stop button
                    Button {
                        if runner.isStreaming { runner.stop() } else { sendMessage() }
                    } label: {
                        Image(systemName: runner.isStreaming ? "stop.fill" : "arrow.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(sendButtonFg)
                            .frame(width: 32, height: 32)
                            .background(sendButtonFill, in: Circle())
                    }
                    .disabled(!canSend && !runner.isStreaming)
                    .buttonStyle(PressScaleButtonStyle(scale: 0.88))
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: canSend)
                    .animation(.spring(response: 0.22, dampingFraction: 0.75), value: runner.isStreaming)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            }
            .frame(minHeight: 56)
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
            && !runner.isStreaming
            && ClaudeRunner.isAvailable()
    }

    private var sendButtonFill: Color {
        if runner.isStreaming { return Kin.statusOffline }
        if canSend { return Kin.accent }
        return Color.clear
    }

    private var sendButtonFg: Color {
        (canSend || runner.isStreaming) ? .white : Kin.textTertiary
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !runner.isStreaming else { return }
        inputText = ""
        runner.send(userMessage: text, agent: agent, memoryContent: store.memoryContent(for: agent))
    }

    private func groupMessages(_ msgs: [ChatMessage]) -> [MessageGroup] {
        var groups: [MessageGroup] = []
        var cur: [ChatMessage] = []
        for msg in msgs {
            if cur.last?.role == msg.role {
                cur.append(msg)
            } else {
                if !cur.isEmpty {
                    groups.append(MessageGroup(
                        id: cur[0].id,
                        role: cur[0].role,
                        messages: cur,
                        date: cur[0].date
                    ))
                }
                cur = [msg]
            }
        }
        if !cur.isEmpty {
            groups.append(MessageGroup(
                id: cur[0].id,
                role: cur[0].role,
                messages: cur,
                date: cur[0].date
            ))
        }
        return groups
    }
}

// MARK: - Message group view

private struct MessageGroupView: View {
    let group: MessageGroup
    let agent: AgentConfig
    var agentStatus: AgentStatus = .offline
    var isStreaming: Bool = false

    private var isUser: Bool { group.role == .user }
    private var senderName: String { isUser ? "You" : agent.name }

    private var timestamp: String? {
        guard let date = group.date else { return nil }
        let fmt = DateFormatter()
        fmt.dateFormat = "h:mm a"
        return fmt.string(from: date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // LEFT — 32pt avatar
            if isUser {
                UserAvatarCircle()
            } else {
                AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 32, avatarPath: agent.avatarPath, status: agentStatus, animated: isStreaming)
            }

            // RIGHT — name + timestamp header + message content
            VStack(alignment: .leading, spacing: 1) {
                // Header row
                HStack(spacing: 8) {
                    Text(senderName)
                        .font(Kin.inter(14, weight: .medium))
                        .foregroundStyle(
                            isUser
                                ? .white
                                : (Color(hex: agent.tint) ?? Kin.accent)
                        )
                    if let ts = timestamp {
                        Text(ts)
                            .font(Kin.inter(11))
                            .foregroundStyle(Kin.textTertiary)
                    }
                }

                ForEach(group.messages) { message in
                    MessageContentView(message: message)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Message content

private struct MessageContentView: View {
    let message: ChatMessage
    @State private var toolsExpanded = false
    @State private var thinkingExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if message.role == .user {
                Text(verbatim: message.content)
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textPrimary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                if !message.thinking.isEmpty {
                    ThinkingRow(text: message.thinking, expanded: $thinkingExpanded)
                }
                if !message.toolCards.isEmpty {
                    ToolCallsRow(cards: message.toolCards, expanded: $toolsExpanded)
                }
                if !message.content.isEmpty {
                    MarkdownText(message.content)
                }
            }
        }
    }
}

// MARK: - User avatar

private struct UserAvatarCircle: View {
    var body: some View {
        ZStack {
            Circle().fill(Kin.avatarBg)
            Text("Y")
                .font(Kin.inter(14, weight: .semibold))
                .foregroundStyle(Kin.textTertiary)
        }
        .frame(width: 32, height: 32)
    }
}

// MARK: - Date divider

private struct DateDividerRow: View {
    let date: Date

    private var label: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let fmt = DateFormatter()
        fmt.dateFormat = "d MMMM yyyy"
        return fmt.string(from: date)
    }

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Kin.border).frame(height: 1)
            Text(label)
                .font(Kin.inter(11, weight: .medium))
                .foregroundStyle(Kin.textSecondary)
                .fixedSize()
            Rectangle().fill(Kin.border).frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Typing group

private struct TypingGroupView: View {
    let agent: AgentConfig
    var agentStatus: AgentStatus = .offline

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 32, avatarPath: agent.avatarPath, status: agentStatus, animated: true)
            TypingRow()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Markdown renderer

struct MarkdownText: View {
    let content: String

    init(_ content: String) { self.content = content }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(parseBlocks(content).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inlineView(text)
                .font(level == 1 ? Kin.inter(20, weight: .bold)
                      : level == 2 ? Kin.inter(17, weight: .semibold)
                      : Kin.inter(15, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)
                .padding(.top, level == 1 ? 6 : 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

        case .paragraph(let text):
            inlineView(text)
                .font(Kin.inter(14))
                .foregroundStyle(Kin.textPrimary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)

        case .bullet(let text, let depth):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textSecondary)
                    .frame(width: 12, alignment: .center)
                inlineView(text)
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textPrimary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(.leading, CGFloat(depth) * 14)

        case .numbered(let label, let text):
            HStack(alignment: .top, spacing: 6) {
                Text(label)
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textSecondary)
                    .frame(minWidth: 20, alignment: .trailing)
                inlineView(text)
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textPrimary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

        case .code(let lang, let code):
            VStack(alignment: .leading, spacing: 0) {
                if !lang.isEmpty {
                    Text(lang)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Kin.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Kin.codeText)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, lang.isEmpty ? 8 : 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))

        case .blockquote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Kin.accent.opacity(0.6))
                    .frame(width: 3)
                inlineView(text)
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textSecondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }

        case .table(let headers, let rows):
            let colCount = max(headers.count, rows.map(\.count).max() ?? 0)
            VStack(alignment: .leading, spacing: 0) {
                // Header row — sidebar-dark bg, compact height
                HStack(spacing: 0) {
                    ForEach(0..<colCount, id: \.self) { col in
                        Text(col < headers.count ? headers[col] : "")
                            .font(Kin.inter(12, weight: .semibold))
                            .foregroundStyle(Kin.textPrimary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if col < colCount - 1 {
                            Rectangle().fill(Kin.border).frame(width: 1)
                        }
                    }
                }
                .background(Kin.sidebarBg)
                Rectangle().fill(Kin.border).frame(height: 1)
                // Body rows — transparent, with both horizontal + vertical dividers
                ForEach(rows.indices, id: \.self) { rowIdx in
                    HStack(spacing: 0) {
                        ForEach(0..<colCount, id: \.self) { col in
                            let cell = col < rows[rowIdx].count ? rows[rowIdx][col] : ""
                            inlineView(cell)
                                .font(Kin.inter(12))
                                .foregroundStyle(Kin.textPrimary)
                                .lineSpacing(2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if col < colCount - 1 {
                                Rectangle().fill(Kin.border).frame(width: 1)
                            }
                        }
                    }
                    if rowIdx < rows.count - 1 {
                        Rectangle().fill(Kin.border).frame(height: 1)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Kin.border, lineWidth: 1))

        case .rule:
            Rectangle()
                .fill(Kin.border)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func inlineView(_ raw: String) -> Text {
        let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: raw, options: opts) {
            return Text(attr)
        }
        return Text(verbatim: raw)
    }
}

enum MDBlock {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case bullet(text: String, depth: Int)
    case numbered(label: String, text: String)
    case code(lang: String, code: String)
    case blockquote(text: String)
    case table(headers: [String], rows: [[String]])
    case rule
}

func parseBlocks(_ raw: String) -> [MDBlock] {
    var blocks: [MDBlock] = []
    let lines = raw.components(separatedBy: "\n")
    var i = 0
    var paraLines: [String] = []

    func flushPara() {
        let joined = paraLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { blocks.append(.paragraph(text: joined)) }
        paraLines = []
    }

    while i < lines.count {
        let line = lines[i]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Fenced code block
        if trimmed.hasPrefix("```") {
            flushPara()
            let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            var code: [String] = []
            i += 1
            while i < lines.count {
                let cl = lines[i].trimmingCharacters(in: .whitespaces)
                if cl.hasPrefix("```") { i += 1; break }
                code.append(lines[i])
                i += 1
            }
            blocks.append(.code(lang: lang, code: code.joined(separator: "\n")))
            continue
        }

        // Heading
        if trimmed.hasPrefix("#") {
            flushPara()
            var level = 0
            var rest = trimmed[trimmed.startIndex...]
            while rest.first == "#" { level += 1; rest = rest.dropFirst() }
            blocks.append(.heading(level: min(level, 3), text: rest.drop(while: { $0 == " " }).description))
            i += 1; continue
        }

        // Horizontal rule
        if trimmed == "---" || trimmed == "***" || trimmed == "___" {
            flushPara(); blocks.append(.rule); i += 1; continue
        }

        // Blockquote
        if trimmed.hasPrefix(">") {
            flushPara()
            let text = trimmed.dropFirst().drop(while: { $0 == " " }).description
            blocks.append(.blockquote(text: text))
            i += 1; continue
        }

        // Table — pipe-prefixed line followed by separator row (|---|---|)
        if trimmed.hasPrefix("|"), i + 1 < lines.count {
            let nextTrimmed = lines[i + 1].trimmingCharacters(in: .whitespaces)
            let isSeparator = nextTrimmed.hasPrefix("|") &&
                nextTrimmed.unicodeScalars.allSatisfy({ $0 == "|" || $0 == "-" || $0 == ":" || $0 == " " })
            if isSeparator {
                flushPara()
                let headers = splitTableRow(trimmed)
                i += 2  // skip header + separator
                var rows: [[String]] = []
                while i < lines.count {
                    let rt = lines[i].trimmingCharacters(in: .whitespaces)
                    guard rt.hasPrefix("|") else { break }
                    rows.append(splitTableRow(rt))
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }
        }

        // Bullet list
        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        let depth = leadingSpaces / 2
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            flushPara()
            blocks.append(.bullet(text: String(trimmed.dropFirst(2)), depth: depth))
            i += 1; continue
        }

        // Numbered list  (e.g. "1. text")
        if let spaceIdx = trimmed.firstIndex(of: "."),
           let _ = Int(trimmed[trimmed.startIndex..<spaceIdx]),
           trimmed.index(after: spaceIdx) < trimmed.endIndex,
           trimmed[trimmed.index(after: spaceIdx)] == " " {
            flushPara()
            let label = String(trimmed[trimmed.startIndex...spaceIdx])
            let text  = String(trimmed[trimmed.index(spaceIdx, offsetBy: 2)...])
            blocks.append(.numbered(label: label, text: text))
            i += 1; continue
        }

        // Empty line = paragraph break
        if trimmed.isEmpty { flushPara(); i += 1; continue }

        paraLines.append(line)
        i += 1
    }

    flushPara()
    return blocks
}

func splitTableRow(_ line: String) -> [String] {
    var s = line
    if s.hasPrefix("|") { s = String(s.dropFirst()) }
    if s.hasSuffix("|") { s = String(s.dropLast()) }
    return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
}

// MARK: - Tool calls row

private struct ToolCallsRow: View {
    let cards: [ToolCard]
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
                    Text("\(cards.count) tool call\(cards.count == 1 ? "" : "s")")
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textSecondary)
                }
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))

            if expanded {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(cards) { card in
                        HStack(spacing: 5) {
                            Image(systemName: card.icon)
                                .font(.system(size: 9))
                                .foregroundStyle(Kin.textTertiary)
                            Text(card.name)
                                .font(Kin.inter(11, weight: .medium))
                                .foregroundStyle(Kin.textSecondary)
                            if !card.summary.isEmpty {
                                Text(card.summary)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(Kin.textTertiary)
                                    .lineLimit(1)
                            }
                        }
                        .padding(.vertical, 1)
                        .padding(.leading, 14)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - Thinking row

private struct ThinkingRow: View {
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
                    Text(text.isEmpty ? "Thinking…" : "Thought")
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textSecondary)
                }
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.92))

            if expanded && !text.isEmpty {
                HStack(alignment: .top, spacing: 0) {
                    Rectangle()
                        .fill(Kin.accent.opacity(0.4))
                        .frame(width: 2)
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

// MARK: - Typing row

private struct TypingRow: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Kin.textSecondary)
                    .frame(width: 4, height: 4)
                    .opacity(phase ? 0.9 : 0.2)
                    .animation(
                        .easeInOut(duration: 0.55).repeatForever(autoreverses: true).delay(Double(i) * 0.18),
                        value: phase
                    )
            }
        }
        .padding(.vertical, 10)
        .onAppear { phase = true }
    }
}

// MARK: - Error row

private struct ErrorRow: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: text)
                .font(Kin.inter(11))
                .foregroundStyle(Kin.textSecondary)
                .textSelection(.enabled)
            Spacer()
            Button("dismiss") { onDismiss() }
                .font(Kin.inter(10))
                .foregroundStyle(Kin.textTertiary)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Kin.errorBg)
    }
}
