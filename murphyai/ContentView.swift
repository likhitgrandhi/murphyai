import SwiftUI

struct ContentView: View {
    @Environment(AgentStore.self) var store
    @Environment(InlineAgentManager.self) var inlineAgent
    @Environment(RunnerStore.self) var runnerStore
    @Environment(SessionStore.self) var session
    @Environment(WorkspaceStore.self) var workspaceStore
    @Environment(SharedChannelStore.self) var sharedChannels
    @Environment(AgentRoster.self) var agentRoster
    @State private var selectedAgentId: String?
    @State private var selectedChannelId: String?
    @State private var selectedSharedChannelId: UUID?
    @State private var channelRunners: [String: ChannelRunner] = [:]

    private var runners: [String: ClaudeRunner] { runnerStore.runners }
    @State private var showNewAgent = false
    @State private var showNewChannel = false
    @State private var showNewDM = false
    @State private var showGlobalSettings = false
    @State private var showInviteMembers = false

    private var selectedAgent: AgentConfig? {
        guard let id = selectedAgentId else { return nil }
        return store.activeAgents.first { $0.id == id }
    }

    private var selectedChannel: Channel? {
        guard let id = selectedChannelId else { return nil }
        return store.activeChannels.first { $0.id == id }
    }

    private var selectedSharedChannel: ServerChannel? {
        guard let id = selectedSharedChannelId else { return nil }
        return sharedChannels.channels.first { $0.id == id }
    }

    private var topBarTitle: String {
        if let ch = selectedSharedChannel {
            return ch.isDM ? "Direct message - \(ch.displayName)" : "Channel - \(ch.displayName)"
        }
        if let channel = selectedChannel { return "Channel - \(channel.name)" }
        if let agent = selectedAgent { return "Direct message - \(agent.name)" }
        return "Direct messages"
    }

    private var topBarIcon: TopBarView.Icon {
        if let ch = selectedSharedChannel { return ch.isDM ? .at : .hash }
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
                        selectedSharedChannelId: $selectedSharedChannelId,
                        showNewAgent: $showNewAgent,
                        showNewChannel: $showNewChannel,
                        showNewDM: $showNewDM,
                        showGlobalSettings: $showGlobalSettings,
                        showInviteMembers: $showInviteMembers,
                        runners: runners
                    )

                    Group {
                        if let shared = selectedSharedChannel {
                            SharedChannelView(channel: shared)
                                .id(shared.id)
                        } else if let channel = selectedChannel, let runner = channelRunners[channel.id] {
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
            NewChannelSheet(onCreated: { result in
                switch result {
                case .shared(let ch):
                    selectedSharedChannelId = ch.id
                    selectedAgentId = nil
                    selectedChannelId = nil
                case .personal(let ch):
                    selectedChannelId = ch.id
                    selectedAgentId = nil
                    selectedSharedChannelId = nil
                }
            })
            .environment(store)
            .environment(sharedChannels)
            .environment(agentRoster)
            .environment(session)
        }
        .sheet(isPresented: $showNewDM) {
            NewDMSheet(onOpened: { ch in
                selectedSharedChannelId = ch.id
                selectedAgentId = nil
                selectedChannelId = nil
            })
            .environment(sharedChannels)
            .environment(session)
        }
        .sheet(isPresented: $showGlobalSettings) {
            GlobalSettingsView().environment(store).environment(inlineAgent).environment(session).environment(workspaceStore)
        }
        .sheet(isPresented: $showInviteMembers) {
            InviteMembersView().environment(workspaceStore)
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
