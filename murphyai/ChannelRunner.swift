import Foundation
import Observation

// MARK: - Per-agent stream state

private final class AgentStreamState {
    var lineBuffer = ""
    var activeMessageId: UUID? = nil
    var process: Process? = nil
}

// MARK: - Channel runner

@Observable
class ChannelRunner {
    var messages: [ChannelMessage] = []
    var activeAgentIds: Set<String> = []
    var claudeError: String? = nil

    private let conversationURL: URL?
    private var streamStates: [String: AgentStreamState] = [:]
    private var chainHopCount = 0
    private let maxChainHops = 3

    init(conversationURL: URL? = nil) {
        self.conversationURL = conversationURL
        if let url = conversationURL,
           let data = try? Data(contentsOf: url),
           var saved = try? JSONDecoder().decode([ChannelMessage].self, from: data) {
            // Clear any stale streaming flags from previous session
            for i in saved.indices { saved[i].isStreaming = false }
            messages = saved
        }
    }

    private func saveMessages() {
        guard let url = conversationURL else { return }
        let toSave = messages.map { msg -> ChannelMessage in
            var m = msg; m.isStreaming = false; return m
        }
        if let data = try? JSONEncoder().encode(toSave) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Public API

    func send(userMessage: String, channel: Channel, agents: [AgentConfig], store: AgentStore) {
        let userMsg = ChannelMessage(sender: .user, content: userMessage)
        messages.append(userMsg)
        saveMessages()
        claudeError = nil
        chainHopCount = 0
        finalizeStaleMessages()

        let members = agents.filter { channel.memberAgentIds.contains($0.id) }
        guard !members.isEmpty else { return }

        let mentioned = parseMentions(userMessage, in: members)

        // Explicit @mentions: single parallel wave, user intent wins.
        if !mentioned.isEmpty {
            executePlan(waves: [mentioned], userMessage: userMessage,
                        channel: channel, agents: agents, store: store)
            return
        }

        // Single member: no planning needed.
        if members.count == 1 {
            executePlan(waves: [[members[0].id]], userMessage: userMessage,
                        channel: channel, agents: agents, store: store)
            return
        }

        // Multi-member: ask the planner to lay out waves.
        Task { @MainActor in
            let waves = await self.plan(message: userMessage, channel: channel, agents: members)
            self.executePlan(waves: waves, userMessage: userMessage,
                             channel: channel, agents: agents, store: store)
        }
    }

    func stopAll() {
        for state in streamStates.values { state.process?.terminate() }
        streamStates.removeAll()
        activeAgentIds.removeAll()
        finalizeStaleMessages()
    }

    private func finalizeStaleMessages() {
        for i in messages.indices where messages[i].isStreaming {
            messages[i].isStreaming = false
            if messages[i].content.isEmpty {
                messages[i].content = "Terminated"
            }
        }
    }

    private func finalizeStreamingMessage(for agentId: String, exitCode: Int32, errText: String) {
        if let idx = messages.indices.last(where: { i in
            if case .agent(let sid) = messages[i].sender {
                return sid == agentId && messages[i].isStreaming
            }
            return false
        }) {
            messages[idx].isStreaming = false
            if exitCode != 0 && messages[idx].content.isEmpty {
                messages[idx].content = errText.isEmpty ? "Error (code \(exitCode))" : errText
            }
            return
        }
        // Agent produced no content at all. Only surface a message on error;
        // silent success (empty output) adds nothing to the channel.
        if exitCode != 0 {
            var msg = ChannelMessage(sender: .agent(id: agentId))
            msg.content = errText.isEmpty ? "Error (code \(exitCode))" : errText
            messages.append(msg)
        }
    }

    func clearHistory() {
        stopAll()
        messages = []
        chainHopCount = 0
        if let url = conversationURL { try? FileManager.default.removeItem(at: url) }
    }

    // MARK: - @ mention parsing

    private func parseMentions(_ text: String, in agents: [AgentConfig]) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "@(\\w+)") else { return [] }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let names = matches.compactMap { m -> String? in
            guard let r = Range(m.range(at: 1), in: text) else { return nil }
            return String(text[r]).lowercased()
        }
        return agents.filter { names.contains($0.name.lowercased()) }.map { $0.id }
    }

    // MARK: - LLM planner

    /// Produces an ordered list of "waves". Agents in the same wave run in parallel;
    /// later waves see earlier waves' outputs via channel history, so they can synthesize.
    private func plan(message: String, channel: Channel, agents: [AgentConfig]) async -> [[String]] {
        guard let path = ClaudeRunner.claudePath, !agents.isEmpty else {
            return [[agents.first?.id].compactMap { $0 }].filter { !$0.isEmpty }
        }

        let agentList = agents.map {
            "id:\($0.id) name:\($0.name) role:\($0.role) skills:[\($0.skills.prefix(5).joined(separator: ","))]"
        }.joined(separator: "\n")

        let recent = messages.suffix(6).compactMap { msg -> String? in
            switch msg.sender {
            case .user: return "User: \(msg.content.prefix(150))"
            case .agent(let id):
                let n = agents.first(where: { $0.id == id })?.name ?? id
                return "\(n): \(msg.content.prefix(150))"
            }
        }.joined(separator: "\n")

        let prompt = """
        Plan how the agents below should respond to the user's message.

        Channel topic: \(channel.topic)
        Agents:
        \(agentList)
        Recent:
        \(recent)
        Message: "\(message)"

        Output an ordered list of "waves". Rules:
        - Agents in the same wave run in parallel.
        - Agents in a later wave see all earlier waves' outputs, so put synthesizers/decision-makers later.
        - Include only agents whose expertise is relevant to THIS message. Skip irrelevant ones.
        - Most messages need a single wave. Use 2+ waves ONLY when one agent's job is to summarize, decide, or build on others' findings.
        - Max 3 waves total. Don't repeat the same agent across waves.

        Reply ONLY with JSON in this exact shape: {"waves":[["id1","id2"],["id3"]]}
        """

        return await withCheckedContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = ["-p", prompt, "--model", ClaudeRunner.selectedModel, "--no-session-persistence"]
            var env = ProcessInfo.processInfo.environment
            env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            proc.environment = env
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            proc.terminationHandler = { _ in
                let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                cont.resume(returning: Self.parsePlan(from: text, agents: agents))
            }
            try? proc.run()
        }
    }

    /// Extracts the first `{"waves":[[...]]}` object from planner output and validates it.
    /// Falls back to a single wave containing the first agent on any failure.
    nonisolated private static func parsePlan(from text: String, agents: [AgentConfig]) -> [[String]] {
        let fallback: [[String]] = agents.isEmpty ? [] : [[agents[0].id]]
        guard let range = text.range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
              let data = String(text[range]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["waves"] as? [[String]]
        else { return fallback }

        let validIds = Set(agents.map { $0.id })
        var seen = Set<String>()
        var waves: [[String]] = []
        for wave in raw.prefix(3) {
            let filtered = wave.filter { validIds.contains($0) && seen.insert($0).inserted }
            if !filtered.isEmpty { waves.append(filtered) }
        }
        return waves.isEmpty ? fallback : waves
    }

    // MARK: - Wave executor

    private func executePlan(waves: [[String]], userMessage: String, channel: Channel,
                             agents: [AgentConfig], store: AgentStore) {
        guard !waves.isEmpty else { return }
        runWave(index: 0, waves: waves, userMessage: userMessage,
                channel: channel, agents: agents, store: store)
    }

    private func runWave(index: Int, waves: [[String]], userMessage: String,
                         channel: Channel, agents: [AgentConfig], store: AgentStore) {
        guard index < waves.count else { return }
        let wave = waves[index]
        guard !wave.isEmpty else {
            runWave(index: index + 1, waves: waves, userMessage: userMessage,
                    channel: channel, agents: agents, store: store)
            return
        }

        var remaining = wave.count
        let onAgentDone: () -> Void = { [weak self] in
            guard let self else { return }
            remaining -= 1
            if remaining == 0 {
                self.runWave(index: index + 1, waves: waves, userMessage: userMessage,
                             channel: channel, agents: agents, store: store)
            }
        }

        for agentId in wave {
            runAgent(id: agentId, promptText: userMessage, channel: channel,
                     agents: agents, store: store, hop: index, onComplete: onAgentDone)
        }
    }

    // MARK: - Run one agent

    private func runAgent(id: String, promptText: String, channel: Channel,
                          agents: [AgentConfig], store: AgentStore, hop: Int,
                          onComplete: (() -> Void)? = nil) {
        guard let agent = agents.first(where: { $0.id == id }) else { onComplete?(); return }
        guard let path = ClaudeRunner.claudePath else { onComplete?(); return }
        guard hop <= maxChainHops else { onComplete?(); return }

        // If already running, stop it and mark its message terminated before relaunching
        if activeAgentIds.contains(id) {
            streamStates[id]?.process?.terminate()
            streamStates.removeValue(forKey: id)
            activeAgentIds.remove(id)
            finalizeStaleMessages()
        }

        let state = AgentStreamState()
        streamStates[id] = state
        activeAgentIds.insert(id)

        // Placeholder message is intentionally NOT appended here. It's created on first
        // content arrival (see handleContent) so that when multiple agents run in parallel,
        // their messages appear in the order content arrives — not launch order — and an
        // agent still thinking is shown as a pending row at the bottom of the list.

        let history = buildChannelHistory(agents: agents)
        let systemPrompt = buildAgentSystemPrompt(agent: agent, channel: channel,
                                                   history: history, memory: store.memoryContent(for: agent))
        let taskPrompt = hop == 0
            ? promptText
            : "Review the conversation above and contribute your expertise as \(agent.name). Be concise."

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)

        var args = [
            "-p", taskPrompt,
            "--system-prompt", systemPrompt,
            "--model", ClaudeRunner.selectedModel,
            "--output-format", "stream-json",
            "--verbose",
            "--include-partial-messages",
            "--permission-mode", "bypassPermissions",
            "--no-session-persistence",
        ]
        let allPaths = Array(Set(channel.folderPaths + agent.folderPaths))
        if !allPaths.isEmpty {
            args += ["--add-dir"] + allPaths
            if let first = allPaths.first {
                process.currentDirectoryURL = URL(fileURLWithPath: first)
            }
        }
        process.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            if let chunk = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in self?.processChunk(chunk, agentId: id) }
            }
        }

        process.terminationHandler = { [weak self] proc in
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errText = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeAgentIds.remove(id)
                self.streamStates.removeValue(forKey: id)
                self.finalizeStreamingMessage(for: id, exitCode: proc.terminationStatus, errText: errText)
                self.saveMessages()

                if proc.terminationStatus == 0 {
                    self.evaluateTriggers(afterAgentId: id, lastPrompt: promptText,
                                         channel: channel, agents: agents, store: store, hop: hop + 1)
                }
                onComplete?()
            }
        }

        do {
            try process.run()
            state.process = process
        } catch {
            activeAgentIds.remove(id)
            streamStates.removeValue(forKey: id)
            finalizeStreamingMessage(for: id, exitCode: 1, errText: "Failed to launch: \(error.localizedDescription)")
            onComplete?()
        }
    }

    // MARK: - Trigger evaluation

    private func evaluateTriggers(afterAgentId: String, lastPrompt: String,
                                   channel: Channel, agents: [AgentConfig],
                                   store: AgentStore, hop: Int) {
        guard hop <= maxChainHops, channel.chainingEnabled else { return }

        let hardRules = channel.triggerRules.filter { $0.afterAgentId == afterAgentId }
        for rule in hardRules where !activeAgentIds.contains(rule.invokeAgentId) {
            runAgent(id: rule.invokeAgentId, promptText: lastPrompt, channel: channel,
                     agents: agents, store: store, hop: hop)
        }
    }

    // MARK: - Stream parsing (per-agent)

    private func processChunk(_ chunk: String, agentId: String) {
        guard let state = streamStates[agentId] else { return }
        state.lineBuffer += chunk
        var lines = state.lineBuffer.components(separatedBy: "\n")
        state.lineBuffer = lines.removeLast()
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty else { continue }
            parseStreamLine(t, agentId: agentId, state: state)
        }
    }

    private func parseStreamLine(_ line: String, agentId: String, state: AgentStreamState) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        switch json["type"] as? String {
        case "assistant":
            guard let msg = json["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { return }
            let isPartial = (json["is_partial"] as? Bool) ?? false
            handleContent(content, isPartial: isPartial, agentId: agentId, state: state)
        case "result":
            if let sub = json["subtype"] as? String, sub == "error",
               let err = json["error"] as? String {
                claudeError = err
            }
        default: break
        }
    }

    private func handleContent(_ blocks: [[String: Any]], isPartial: Bool,
                                agentId: String, state: AgentStreamState) {
        var text = ""
        var thinking = ""
        var cards: [ToolCard] = []

        for block in blocks {
            switch block["type"] as? String {
            case "text":    text    += (block["text"]    as? String) ?? ""
            case "thinking": thinking += (block["thinking"] as? String) ?? ""
            case "tool_use":
                if let name = block["name"] as? String {
                    cards.append(makeToolCard(name: name, input: block["input"] as? [String: Any] ?? [:]))
                }
            default: break
            }
        }

        if let msgId = state.activeMessageId,
           let idx = messages.firstIndex(where: { $0.id == msgId }) {
            if !text.isEmpty { messages[idx].content = text }
            if !thinking.isEmpty { messages[idx].thinking = thinking }
            if !cards.isEmpty { messages[idx].toolCards = cards }
        } else if !text.isEmpty {
            // Only promote the agent out of the pending row once it starts producing its
            // final text answer. Thinking blocks and tool calls alone keep the agent inside
            // the overlap indicator — this prevents rows from being inserted mid-task and
            // keeps parallel runs visually stable until each agent is ready to reply.
            // Thinking/tool cards collected so far are attached to the newly created message
            // so they remain available when the answer appears.
            var msg = ChannelMessage(sender: .agent(id: agentId), isStreaming: true)
            msg.content = text
            msg.thinking = thinking
            msg.toolCards = cards
            messages.append(msg)
            state.activeMessageId = msg.id
        }
    }

    // MARK: - Context builders

    private func buildChannelHistory(agents: [AgentConfig]) -> String {
        guard !messages.isEmpty else { return "" }

        var chars = 0
        let budget = 14_000
        var segments: [String] = []

        for msg in messages.reversed() {
            let label: String
            switch msg.sender {
            case .user: label = "User"
            case .agent(let id): label = agents.first(where: { $0.id == id })?.name ?? id
            }
            var body = msg.content
            if body.count > 1000 { body = String(body.prefix(1000)) + "…" }
            let line = "\(label): \(body)"
            chars += line.count + 2
            if chars > budget { break }
            segments.insert(line, at: 0)
        }

        return segments.joined(separator: "\n\n")
    }

    private func buildAgentSystemPrompt(agent: AgentConfig, channel: Channel,
                                         history: String, memory: String) -> String {
        var parts: [String] = []

        parts.append("""
        You are \(agent.name), a \(agent.role) in channel #\(channel.name).
        Channel topic: \(channel.topic)
        Other members may also contribute. Respond only as \(agent.name).
        """)

        if !channel.folderPaths.isEmpty || !agent.folderPaths.isEmpty {
            let allPaths = Array(Set(channel.folderPaths + agent.folderPaths))
            let list = allPaths.map { "- \($0)" }.joined(separator: "\n")
            parts.append("""
            ## Working Directories
            Working directory: \(allPaths[0])
            Access:\n\(list)
            Search within these directories only. Never run `find /` or `ls /`.
            """)
        }

        if !agent.skills.isEmpty {
            parts.append("## Skills\n" + agent.skills.map { "- \($0)" }.joined(separator: "\n"))
        }

        parts.append(agent.systemPrompt)

        if !history.isEmpty {
            parts.append("## Channel History\n\(history)")
        }

        let mem = memory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !mem.isEmpty { parts.append("## Memory\n\(mem)") }

        return parts.joined(separator: "\n\n")
    }

    private func makeToolCard(name: String, input: [String: Any]) -> ToolCard {
        let summary: String
        switch name {
        case "Read", "Edit", "Write":
            summary = URL(fileURLWithPath: input["file_path"] as? String ?? "").lastPathComponent
        case "Bash":
            let cmd = (input["command"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            summary = String((cmd.components(separatedBy: "\n").first ?? cmd).prefix(60))
        case "Glob":   summary = input["pattern"] as? String ?? ""
        case "Grep":   summary = input["pattern"] as? String ?? ""
        default:       summary = input.values.compactMap { "\($0)" }.first ?? ""
        }
        let icon: String
        switch name {
        case "Read":           icon = "doc.text"
        case "Edit", "Write":  icon = "pencil"
        case "Bash":           icon = "terminal"
        case "Glob", "Grep":   icon = "magnifyingglass"
        default:               icon = "gearshape"
        }
        return ToolCard(icon: icon, name: name, summary: summary)
    }
}
