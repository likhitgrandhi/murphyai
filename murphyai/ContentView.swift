import SwiftUI

struct ContentView: View {
    @Environment(AgentStore.self) var store
    @State private var selectedAgentId: String?
    @State private var selectedChannelId: String?
    @State private var runners: [String: ClaudeRunner] = [:]
    @State private var channelRunners: [String: ChannelRunner] = [:]
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

    var body: some View {
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
            .padding(.top, 28)
        }
        .background(Kin.serverBg.ignoresSafeArea())
        .frame(minWidth: 960, minHeight: 600)
        .toolbar(.hidden, for: .automatic)
        .sheet(isPresented: $showNewAgent) {
            NewAgentSheet(editingAgent: nil).environment(store)
        }
        .sheet(isPresented: $showNewChannel) {
            NewChannelSheet().environment(store)
        }
        .sheet(isPresented: $showGlobalSettings) {
            GlobalSettingsView().environment(store)
        }
        .onAppear {
            seedRunners()
            seedChannelRunners()
            if selectedAgentId == nil && selectedChannelId == nil {
                selectedAgentId = store.activeAgents.first?.id
            }
        }
        .onChange(of: store.agents.count) { seedRunners() }
        .onChange(of: store.channels.count) { seedChannelRunners() }
        .onChange(of: selectedAgentId) { _, newId in
            if let id = newId, runners[id] == nil {
                runners[id] = ClaudeRunner()
            }
        }
        .onChange(of: selectedChannelId) { _, newId in
            if let id = newId, channelRunners[id] == nil {
                channelRunners[id] = ChannelRunner()
            }
        }
    }

    private func seedRunners() {
        for agent in store.activeAgents where runners[agent.id] == nil {
            let url = store.agentDirectory(for: agent).appendingPathComponent("conversation.json")
            runners[agent.id] = ClaudeRunner(conversationURL: url)
        }
    }

    private func seedChannelRunners() {
        for channel in store.activeChannels where channelRunners[channel.id] == nil {
            let url = store.channelDirectory(for: channel).appendingPathComponent("conversation.json")
            channelRunners[channel.id] = ChannelRunner(conversationURL: url)
        }
    }
}
