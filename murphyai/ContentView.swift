import SwiftUI

struct ContentView: View {
    @Environment(AgentStore.self) var store
    @Environment(InlineAgentManager.self) var inlineAgent
    @Environment(RunnerStore.self) var runnerStore
    @State private var selectedAgentId: String?
    @State private var selectedChannelId: String?
    @State private var channelRunners: [String: ChannelRunner] = [:]

    private var runners: [String: ClaudeRunner] { runnerStore.runners }
    @State private var showNewAgent = false
    @State private var showNewChannel = false
    @State private var showGlobalSettings = false

    private var selectedAgent: AgentConfig? {
        guard let id = selectedAgentId else { return nil }
        return store.activeAgents.first { $0.id == id }
    }

    private var selectedChannel: Channel? {
        guard let id = selectedChannelId else { return nil }
        return store.activeChannels.first { $0.id == id }
    }

    private var topBarTitle: String {
        if let channel = selectedChannel { return "Channel - \(channel.name)" }
        if let agent = selectedAgent { return "Direct message - \(agent.name)" }
        return "Direct messages"
    }

    private var topBarIcon: TopBarView.Icon {
        if selectedChannel != nil { return .hash }
        if selectedAgent != nil { return .at }
        return .messages
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(title: topBarTitle, icon: topBarIcon)

            HStack(spacing: 0) {
                // Server strip — outside the bordered container, full height
                ServerStripView(showNewChannel: $showNewChannel)

                // Bordered container: channel sidebar + content area
                HStack(spacing: 0) {
                    SidebarView(
                        selectedAgentId: $selectedAgentId,
                        selectedChannelId: $selectedChannelId,
                        showNewAgent: $showNewAgent,
                        showNewChannel: $showNewChannel,
                        showGlobalSettings: $showGlobalSettings,
                        runners: runners
                    )

                    Group {
                        if let channel = selectedChannel, let runner = channelRunners[channel.id] {
                            ChannelView(channel: channel, runner: runner)
                                .id(channel.id)
                        } else if let agent = selectedAgent, let runner = runners[agent.id] {
                            ThreadView(agent: agent, runner: runner)
                                .id(agent.id)
                        } else {
                            Kin.bg.ignoresSafeArea()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12))
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: 12)
                        .strokeBorder(Kin.border, lineWidth: 1)
                }
            }
        }
        .background(Kin.serverBg.ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 960, minHeight: 600)
        .toolbar(.hidden, for: .automatic)
        .sheet(isPresented: $showNewAgent) {
            NewAgentSheet(editingAgent: nil).environment(store)
        }
        .sheet(isPresented: $showNewChannel) {
            NewChannelSheet().environment(store)
        }
        .sheet(isPresented: $showGlobalSettings) {
            GlobalSettingsView().environment(store).environment(inlineAgent)
        }
        .onAppear {
            seedRunners()
            seedChannelRunners()
            if selectedAgentId == nil && selectedChannelId == nil {
                selectedAgentId = store.activeAgents.first?.id
            }
            Task { await store.refreshPixabotAvatars() }
        }
        .onChange(of: store.agents.count) { seedRunners() }
        .onChange(of: store.channels.count) { seedChannelRunners() }
        .onChange(of: selectedAgentId) { _, newId in
            guard let id = newId, runnerStore.runners[id] == nil,
                  let agent = store.agents.first(where: { $0.id == id }) else { return }
            _ = runnerStore.runner(for: agent, store: store)
        }
        .onChange(of: selectedChannelId) { _, newId in
            if let id = newId, channelRunners[id] == nil {
                channelRunners[id] = ChannelRunner()
            }
        }
    }

    private func seedRunners() {
        runnerStore.seed(for: store.activeAgents, store: store)
    }

    private func seedChannelRunners() {
        for channel in store.activeChannels where channelRunners[channel.id] == nil {
            let url = store.channelDirectory(for: channel).appendingPathComponent("conversation.json")
            channelRunners[channel.id] = ChannelRunner(conversationURL: url)
        }
    }
}
