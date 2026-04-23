import Foundation
import Observation

@Observable
@MainActor
final class RunnerStore {
    var runners: [String: ClaudeRunner] = [:]

    func runner(for agent: AgentConfig, store: AgentStore) -> ClaudeRunner {
        if let existing = runners[agent.id] { return existing }
        let url = store.agentDirectory(for: agent).appendingPathComponent("conversation.json")
        let runner = ClaudeRunner(conversationURL: url)
        runners[agent.id] = runner
        return runner
    }

    func seed(for agents: [AgentConfig], store: AgentStore) {
        for agent in agents where runners[agent.id] == nil {
            let url = store.agentDirectory(for: agent).appendingPathComponent("conversation.json")
            runners[agent.id] = ClaudeRunner(conversationURL: url)
        }
    }
}
