import Foundation
import Observation

// MARK: - Data models

struct ToolCard: Identifiable, Codable {
    let id: UUID
    let icon: String
    let name: String
    let summary: String

    init(icon: String, name: String, summary: String) {
        self.id = UUID()
        self.icon = icon; self.name = name; self.summary = summary
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    var thinking: String
    var toolCards: [ToolCard]
    let date: Date

    enum Role: String, Codable { case user, assistant }

    init(role: Role, content: String, thinking: String = "", toolCards: [ToolCard] = []) {
        self.id = UUID(); self.role = role; self.content = content
        self.thinking = thinking; self.toolCards = toolCards; self.date = Date()
    }
}

// MARK: - Runner

@Observable
class ClaudeRunner {
    var messages: [ChatMessage] = []
    var isStreaming = false
    var claudeError: String? = nil

    private let conversationURL: URL?

    init(conversationURL: URL? = nil) {
        self.conversationURL = conversationURL
        if let url = conversationURL,
           let data = try? Data(contentsOf: url),
           let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = saved
        }
    }

    private func saveMessages() {
        guard let url = conversationURL,
              let data = try? JSONEncoder().encode(messages) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static let claudePath: String? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/usr/bin/claude",
        ]
        if let found = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return found
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["claude"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/bin:/bin:/usr/sbin:/sbin:\(home)/.local/bin"
        proc.environment = env
        let pipe = Pipe()
        proc.standardOutput = pipe
        try? proc.run()
        proc.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return out.isEmpty ? nil : out
    }()

    static func isAvailable() -> Bool { claudePath != nil }

    /// User-selected Claude model (CLI alias). Defaults to `sonnet` (Sonnet 4.6).
    /// Backed by @AppStorage("kinClaudeModel") in the settings panel.
    static var selectedModel: String {
        UserDefaults.standard.string(forKey: "kinClaudeModel") ?? "sonnet"
    }

    private var currentProcess: Process?
    private var lineBuffer = ""
    private var currentRoundId: UUID?

    // MARK: - Send

    func send(userMessage: String, agent: AgentConfig, memoryContent: String) {
        guard !isStreaming, let path = Self.claudePath else { return }

        let history = buildConversationHistory()
        messages.append(ChatMessage(role: .user, content: userMessage))
        saveMessages()
        isStreaming = true
        claudeError = nil
        lineBuffer = ""
        currentRoundId = nil

        let systemPrompt = buildSystemPrompt(agent: agent, memory: memoryContent, history: history)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)

        var args: [String] = [
            "-p", userMessage,
            "--system-prompt", systemPrompt,
            "--model", Self.selectedModel,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", "bypassPermissions",
            "--no-session-persistence",
        ]
        if !agent.folderPaths.isEmpty {
            args += ["--add-dir"] + agent.folderPaths
        }
        process.arguments = args

        // Set working directory to the agent's primary folder so relative paths resolve correctly
        if let firstPath = agent.folderPaths.first {
            process.currentDirectoryURL = URL(fileURLWithPath: firstPath)
        }

        var env = ProcessInfo.processInfo.environment
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError  = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            if let chunk = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in self?.processChunk(chunk) }
            }
        }

        process.terminationHandler = { [weak self] proc in
            let exitCode = proc.terminationStatus
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor [weak self] in
                guard let self else { return }
                let hasContent = self.messages.last(where: { $0.role == .assistant })?.content.isEmpty == false
                if exitCode != 0 || (!hasContent && !errText.isEmpty) {
                    self.claudeError = errText.isEmpty
                        ? "claude exited with code \(exitCode)"
                        : errText
                }
                self.isStreaming = false
                self.currentRoundId = nil
                self.currentProcess = nil
                self.saveMessages()
            }
        }

        do {
            try process.run()
            currentProcess = process
        } catch {
            isStreaming = false
            claudeError = "Failed to launch claude: \(error.localizedDescription)"
        }
    }

    func stop() {
        currentProcess?.terminate()
        isStreaming = false
        currentRoundId = nil
    }

    func clearHistory() {
        stop()
        messages = []
        if let url = conversationURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - Stream-JSON parsing

    private func processChunk(_ chunk: String) {
        lineBuffer += chunk
        var lines = lineBuffer.components(separatedBy: "\n")
        lineBuffer = lines.removeLast()
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            parseStreamLine(trimmed)
        }
    }

    private func parseStreamLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        switch json["type"] as? String {
        case "assistant":
            guard let msg = json["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { return }
            let isPartial = (json["is_partial"] as? Bool) ?? false
            handleAssistantContent(content, isPartial: isPartial)

        case "result":
            if let subtype = json["subtype"] as? String, subtype == "error",
               let errMsg = json["error"] as? String {
                claudeError = errMsg
            }

        default:
            break
        }
    }

    private func handleAssistantContent(_ content: [[String: Any]], isPartial: Bool) {
        var text = ""
        var thinking = ""
        var cards: [ToolCard] = []

        for block in content {
            switch block["type"] as? String {
            case "text":
                text += (block["text"] as? String) ?? ""
            case "thinking":
                thinking += (block["thinking"] as? String) ?? ""
            case "tool_use":
                if let name = block["name"] as? String {
                    let input = block["input"] as? [String: Any] ?? [:]
                    cards.append(makeToolCard(name: name, input: input))
                }
            default:
                break
            }
        }

        if let rid = currentRoundId, let idx = messages.firstIndex(where: { $0.id == rid }) {
            messages[idx].content = text
            messages[idx].thinking = thinking
            if !cards.isEmpty { messages[idx].toolCards = cards }
        } else {
            var msg = ChatMessage(role: .assistant, content: text, thinking: thinking)
            msg.toolCards = cards
            messages.append(msg)
            currentRoundId = msg.id
        }

        if !isPartial { currentRoundId = nil }
    }

    // MARK: - Helpers

    private func makeToolCard(name: String, input: [String: Any]) -> ToolCard {
        let summary: String
        switch name {
        case "Read", "Edit", "Write", "NotebookEdit":
            let path = input["file_path"] as? String ?? ""
            summary = URL(fileURLWithPath: path).lastPathComponent
        case "Bash":
            let cmd = (input["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            summary = String((cmd.components(separatedBy: "\n").first ?? cmd).prefix(60))
        case "Glob":
            summary = input["pattern"] as? String ?? ""
        case "Grep":
            summary = input["pattern"] as? String ?? ""
        case "WebSearch":
            summary = input["query"] as? String ?? ""
        default:
            summary = input.values.compactMap { "\($0)" }.first ?? ""
        }

        let icon: String
        switch name {
        case "Read":               icon = "doc.text"
        case "Edit", "Write":      icon = "pencil"
        case "Bash":               icon = "terminal"
        case "Glob", "Grep":       icon = "magnifyingglass"
        case "WebSearch":          icon = "globe"
        case "NotebookEdit":       icon = "book"
        default:                   icon = "gearshape"
        }

        return ToolCard(icon: icon, name: name, summary: summary)
    }

    private func buildConversationHistory() -> String {
        // Work backwards through messages (excluding the current user message which hasn't been
        // appended yet), accumulating up to 15 messages and 15,000 chars total.
        let maxMessages = 15
        let maxTotalChars = 15_000
        let maxMessageChars = 1_000

        let prior = messages  // snapshot before the new user message is appended
        guard !prior.isEmpty else { return "" }

        var segments: [String] = []
        var totalChars = 0

        for msg in prior.reversed() {
            guard segments.count < maxMessages else { break }
            guard totalChars < maxTotalChars else { break }

            let label: String
            switch msg.role {
            case .user:      label = "User"
            case .assistant: label = "Assistant"
            }

            var body = msg.content
            if body.count > maxMessageChars {
                body = String(body.prefix(maxMessageChars)) + "…"
            }

            let segment = "\(label): \(body)"
            let segmentCost = segment.count + 2  // +2 for the "\n\n" separator

            guard totalChars + segmentCost <= maxTotalChars else { break }
            segments.append(segment)
            totalChars += segmentCost
        }

        guard !segments.isEmpty else { return "" }

        // Segments are in reverse-chronological order; flip back to chronological.
        let chronological = segments.reversed().joined(separator: "\n\n")
        return "## Conversation History\n\(chronological)"
    }

    private func buildSystemPrompt(agent: AgentConfig, memory: String, history: String = "") -> String {
        var parts: [String] = []

        if !agent.folderPaths.isEmpty {
            let list = agent.folderPaths.map { "- \($0)" }.joined(separator: "\n")
            parts.append("""
            ## Working Directories
            Your working directory is set to: \(agent.folderPaths[0])
            You also have access to:
            \(list)

            IMPORTANT: Always search, read, and write files within these directories only. \
            Use relative paths when possible. Never run commands that traverse above these paths (e.g. `find /`, `ls /`). \
            When looking for files, start your search from the working directory.
            """)
        }

        if !agent.skills.isEmpty {
            parts.append("## Skills\n" + agent.skills.map { "- \($0)" }.joined(separator: "\n"))
        }

        let trimmedHistory = history.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedHistory.isEmpty { parts.append(trimmedHistory) }

        parts.append(agent.systemPrompt)
        let mem = memory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mem.isEmpty { parts.append("## Memory\n\(mem)") }
        return parts.joined(separator: "\n\n")
    }

    func presenceStatus(at now: Date = Date()) -> AgentStatus {
        if isStreaming { return .online }
        guard let lastDate = messages.last?.date else { return .offline }
        let elapsed = now.timeIntervalSince(lastDate)
        if elapsed < 5 * 60  { return .online }
        if elapsed < 10 * 60 { return .snooze }
        return .offline
    }
}
