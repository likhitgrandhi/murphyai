import Foundation

struct GeneratedAgent {
    let name: String
    let role: String
    let systemPrompt: String
    let skills: [String]
    let folderPaths: [String]
}

enum AgentGenerationError: LocalizedError {
    case claudeBinaryMissing
    case processFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .claudeBinaryMissing:
            return "Claude CLI not found. Install it from claude.ai/download."
        case .processFailed(let msg):
            return msg.isEmpty ? "Claude couldn't generate a response." : msg
        case .invalidResponse:
            return "Claude's response wasn't in the expected format."
        }
    }
}

enum AgentGenerator {
    static func generate(description: String) async throws -> GeneratedAgent {
        guard let path = ClaudeRunner.claudePath else {
            throw AgentGenerationError.claudeBinaryMissing
        }

        let prompt = """
        You design agent personas for a desktop AI app. A non-technical user described what they need. Turn it into a full agent config.

        User description:
        \"\"\"
        \(description)
        \"\"\"

        Return ONLY a single JSON object, no prose, no markdown fences. Schema:
        {
          "name": "short 1-2 word friendly name, TitleCase, no quotes",
          "role": "one line, under 80 chars, format: '<Role> · <scope>'",
          "systemPrompt": "150-350 words. Write as a second-person instruction to the agent. Cover: purpose, tone, output format, what to prioritize, what to avoid. Be specific to this user's description — no generic filler.",
          "skills": ["3 to 6 short skills, lowercase"],
          "folderPaths": ["only absolute paths if the description clearly mentions them, else empty array"]
        }
        """

        let rawOutput = try await runClaude(path: path, prompt: prompt)
        return try parse(rawOutput)
    }

    private static func runClaude(path: String, prompt: String) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: path)
            proc.arguments = [
                "-p", prompt,
                "--model", ClaudeRunner.selectedModel,
                "--no-session-persistence",
            ]
            var env = ProcessInfo.processInfo.environment
            env["HOME"] = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            proc.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            proc.terminationHandler = { p in
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: outData, encoding: .utf8) ?? ""
                let err = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if p.terminationStatus != 0 {
                    cont.resume(throwing: AgentGenerationError.processFailed(err))
                } else {
                    cont.resume(returning: out)
                }
            }
            do {
                try proc.run()
            } catch {
                cont.resume(throwing: AgentGenerationError.processFailed(error.localizedDescription))
            }
        }
    }

    private static func parse(_ text: String) throws -> GeneratedAgent {
        guard let range = text.range(of: #"\{[\s\S]*\}"#, options: .regularExpression),
              let data = String(text[range]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AgentGenerationError.invalidResponse(text) }

        let name = (json["name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let role = (json["role"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let systemPrompt = (json["systemPrompt"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let skills = (json["skills"] as? [String])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let folderPaths = (json["folderPaths"] as? [String])?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        guard !name.isEmpty, !systemPrompt.isEmpty else {
            throw AgentGenerationError.invalidResponse(text)
        }

        return GeneratedAgent(
            name: String(name.prefix(40)),
            role: String(role.prefix(80)),
            systemPrompt: systemPrompt,
            skills: Array(skills.prefix(6)),
            folderPaths: folderPaths
        )
    }
}
