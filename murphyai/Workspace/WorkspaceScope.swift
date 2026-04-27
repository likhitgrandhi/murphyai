import SwiftUI

// Owns the workspace-scoped stores for a given workspace.
// Keyed by workspace ID so SwiftUI rebuilds cleanly on workspace switch.
struct WorkspaceScope: View {
    let workspace: KinWorkspace
    let content: () -> AnyView

    @State private var agentStore: AgentStore
    @State private var runnerStore = RunnerStore()
    @State private var inlineAgent: InlineAgentManager
    @State private var sharedChannels = SharedChannelStore()
    @State private var agentRoster = AgentRoster()
    @State private var channelRunner = SharedChannelRunner()

    init(workspace: KinWorkspace, @ViewBuilder content: @escaping () -> some View) {
        self.workspace = workspace
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".kin/workspaces/\(workspace.id.uuidString)", isDirectory: true)
        let store = AgentStore(workspaceDir: dir)
        _agentStore = State(initialValue: store)
        _inlineAgent = State(initialValue: InlineAgentManager())
        self.content = { AnyView(content()) }
    }

    var body: some View {
        content()
            .environment(agentStore)
            .environment(runnerStore)
            .environment(inlineAgent)
            .environment(sharedChannels)
            .environment(agentRoster)
            .environment(channelRunner)
            .task(id: workspace.id) {
                inlineAgent.bootstrap(store: agentStore, runnerStore: runnerStore)
                async let _channels: () = sharedChannels.bind(workspaceId: workspace.id)
                async let _roster: () = agentRoster.bind(workspaceId: workspace.id)
                _ = await (_channels, _roster)
                channelRunner.bind(store: sharedChannels, roster: agentRoster)
            }
            .id(workspace.id)
    }
}
