import SwiftUI
import AppKit

// MARK: - Two-column settings shell (Discord-style)

private struct SettingsShell<Sidebar: View, Content: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                sidebar()
                Spacer(minLength: 0)
            }
            .frame(width: 218)
            .frame(maxHeight: .infinity)
            .background(Kin.sidebarBg)

            Rectangle().fill(Kin.border).frame(width: 1)

            VStack(spacing: 0) {
                content()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Kin.bg)
        }
        .frame(width: 760, height: 520)
        .overlay(alignment: .topTrailing) {
            Button { isPresented = false } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Kin.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(Kin.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(14)
        }
    }
}

// MARK: - Right-panel page wrapper

private struct SettingsPage<C: View>: View {
    let title: String
    @ViewBuilder let content: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(Kin.inter(20, weight: .bold))
                .foregroundStyle(Kin.textPrimary)
                .padding(.horizontal, 40)
                .padding(.top, 36)
                .padding(.bottom, 16)

            Rectangle()
                .fill(Kin.border)
                .frame(height: 1)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    content()
                }
                .padding(.horizontal, 40)
                .padding(.top, 28)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Sidebar helpers

private struct SidebarNavItem: View {
    let label: String
    let isSelected: Bool
    var isDanger: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(Kin.inter(13))
                    .foregroundStyle(
                        isDanger
                            ? Color.red.opacity(0.75)
                            : isSelected ? Kin.textPrimary : Kin.textSecondary
                    )
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected && !isDanger ? Kin.sidebarSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
    }
}

private struct SidebarSectionHeader: View {
    let label: String
    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Kin.textTertiary)
            .textCase(.uppercase)
            .tracking(0.6)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Shared field helpers

private struct KinField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    init(_ label: String, placeholder: String, text: Binding<String>) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Kin.textTertiary)
                .textCase(.uppercase)
                .tracking(0.3)
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct SettingsSubsection<C: View>: View {
    let title: String
    @ViewBuilder let content: () -> C

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Kin.inter(16, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)
            content()
        }
    }
}

// MARK: - Agent settings modal

enum AgentSettingsSection: Hashable {
    case identity, systemPrompt, skills, folderAccess, memory, fireAgent

    var label: String {
        switch self {
        case .identity:     return "Identity"
        case .systemPrompt: return "System Prompt"
        case .skills:       return "Skills"
        case .folderAccess: return "Folder Access"
        case .memory:       return "Memory"
        case .fireAgent:    return "Fire Agent"
        }
    }
}

struct AgentSettingsModal: View {
    let agent: AgentConfig
    @Environment(AgentStore.self) var store
    @Binding var isPresented: Bool
    @State private var draft: AgentConfig
    @State private var selection: AgentSettingsSection = .identity
    @State private var newSkill = ""
    @State private var showFireConfirm = false

    init(agent: AgentConfig, isPresented: Binding<Bool>) {
        self.agent = agent
        _isPresented = isPresented
        _draft = State(initialValue: agent)
    }

    var body: some View {
        SettingsShell(isPresented: $isPresented) {
            agentSidebar
        } content: {
            agentContent
        }
        .onChange(of: draft) { _, _ in store.save(draft) }
    }

    // MARK: Sidebar

    private var agentSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                AgentAvatarCircle(
                    name: draft.name.isEmpty ? "?" : draft.name,
                    tint: draft.tint,
                    size: 36,
                    avatarPath: draft.avatarPath
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.name.isEmpty ? "Agent" : draft.name)
                        .font(Kin.inter(13, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                        .lineLimit(1)
                    Text(draft.role.isEmpty ? "No role" : draft.role)
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textTertiary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().opacity(0.3)

            SidebarSectionHeader(label: "Agent Settings")
            ForEach(
                [AgentSettingsSection.identity, .systemPrompt, .skills, .folderAccess, .memory],
                id: \.self
            ) { sec in
                SidebarNavItem(label: sec.label, isSelected: selection == sec) { selection = sec }
            }

            SidebarSectionHeader(label: "Danger Zone")
            SidebarNavItem(
                label: "Fire \(draft.name)",
                isSelected: selection == .fireAgent,
                isDanger: true
            ) { selection = .fireAgent }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var agentContent: some View {
        switch selection {
        case .identity:
            SettingsPage(title: "Identity") { identityContent }
        case .systemPrompt:
            SettingsPage(title: "System Prompt") { promptContent }
        case .skills:
            SettingsPage(title: "Skills") { skillsContent }
        case .folderAccess:
            SettingsPage(title: "Folder Access") { agentFoldersContent }
        case .memory:
            SettingsPage(title: "Memory") { memoryContent }
        case .fireAgent:
            SettingsPage(title: "Danger Zone") { agentDangerContent }
        }
    }

    private var identityContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSubsection(title: "Profile") {
                KinField("Name", placeholder: "Agent name", text: $draft.name)
                KinField("Role", placeholder: "One-line description", text: $draft.role)
            }
            SettingsSubsection(title: "Appearance") {
                KinField("Icon (SF Symbol)", placeholder: "hammer.fill, magnifyingglass…", text: $draft.icon)
                KinField("Tint (hex)", placeholder: "#7BA4FF", text: $draft.tint)
            }
        }
    }

    private var promptContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Instructions prepended to every conversation with this agent.")
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textSecondary)
            TextEditor(text: $draft.systemPrompt)
                .frame(minHeight: 200)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .background(Kin.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var skillsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capability descriptors prepended to the system prompt.")
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textSecondary)

            if !draft.skills.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(draft.skills, id: \.self) { skill in
                        HStack(spacing: 4) {
                            Text(skill)
                                .font(.system(size: 12))
                                .foregroundStyle(Kin.textSecondary)
                            Button {
                                draft.skills.removeAll { $0 == skill }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(Kin.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Add skill…", text: $newSkill)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addSkill() }
                Button("Add") { addSkill() }
                    .buttonStyle(.borderedProminent)
                    .tint(Kin.accent)
                    .controlSize(.small)
                    .disabled(newSkill.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addSkill() {
        let trimmed = newSkill.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !draft.skills.contains(trimmed) else { return }
        draft.skills.append(trimmed)
        newSkill = ""
    }

    @ViewBuilder
    private var agentFoldersContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders this agent can read and write.")
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textSecondary)

            if draft.folderPaths.isEmpty {
                Text("No folders granted")
                    .font(Kin.inter(13))
                    .foregroundStyle(Kin.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.folderPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundStyle(Kin.textTertiary)
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Kin.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                draft.folderPaths.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Kin.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Button("Add Folder…") { pickAgentFolder() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func pickAgentFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            let path = url.path
            if !draft.folderPaths.contains(path) { draft.folderPaths.append(path) }
        }
    }

    private var memoryContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Persistent context carried across conversations.")
                    .font(Kin.inter(13))
                    .foregroundStyle(Kin.textSecondary)
                Spacer()
                Button("Clear") {
                    store.clearMemory(for: agent)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.red.opacity(0.7))
            }

            let content = store.memoryContent(for: agent).trimmingCharacters(in: .whitespacesAndNewlines)
            if content.isEmpty {
                Text("No memory yet.")
                    .font(Kin.inter(13))
                    .foregroundStyle(Kin.textTertiary)
            } else {
                ScrollView(showsIndicators: false) {
                    Text(content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Kin.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 240)
                .padding(12)
                .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    @ViewBuilder
    private var agentDangerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fire \(agent.name)")
                .font(Kin.inter(16, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)
            Text("This will permanently remove \(agent.name) along with all their memory and history. This cannot be undone.")
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textSecondary)
            Button("Fire \(agent.name)") { showFireConfirm = true }
                .buttonStyle(.bordered)
                .foregroundStyle(.red.opacity(0.85))
                .controlSize(.regular)
                .confirmationDialog(
                    "Fire \(agent.name)?",
                    isPresented: $showFireConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Fire \(agent.name)", role: .destructive) {
                        store.delete(agent)
                        isPresented = false
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently deletes \(agent.name) and all their data. This cannot be undone.")
                }
        }
        .padding(16)
        .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Channel settings modal

enum ChannelSettingsSection: Hashable {
    case overview, members, folderAccess, chaining, conversation, deleteChannel

    var label: String {
        switch self {
        case .overview:      return "Overview"
        case .members:       return "Members"
        case .folderAccess:  return "Folder Access"
        case .chaining:      return "Agent Chaining"
        case .conversation:  return "Conversation"
        case .deleteChannel: return "Delete Channel"
        }
    }
}

struct ChannelSettingsModal: View {
    let channel: Channel
    let runner: ChannelRunner
    @Environment(AgentStore.self) var store
    @Binding var isPresented: Bool
    @State private var draft: Channel
    @State private var selection: ChannelSettingsSection = .overview
    @State private var showDeleteConfirm = false
    @State private var showClearConfirm = false

    init(channel: Channel, runner: ChannelRunner, isPresented: Binding<Bool>) {
        self.channel = channel
        self.runner = runner
        _isPresented = isPresented
        _draft = State(initialValue: channel)
    }

    var body: some View {
        SettingsShell(isPresented: $isPresented) {
            channelSidebar
        } content: {
            channelContent
        }
        .onChange(of: draft) { _, _ in store.saveChannel(draft) }
    }

    // MARK: Sidebar

    private var channelSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Kin.surface)
                        .frame(width: 36, height: 36)
                    Text("#")
                        .font(Kin.inter(16, weight: .bold))
                        .foregroundStyle(Kin.textSecondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.name.isEmpty ? "channel" : draft.name)
                        .font(Kin.inter(13, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                        .lineLimit(1)
                    if !draft.topic.isEmpty {
                        Text(draft.topic)
                            .font(Kin.inter(11))
                            .foregroundStyle(Kin.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider().opacity(0.3)

            SidebarSectionHeader(label: "Channel Settings")
            ForEach(
                [ChannelSettingsSection.overview, .members, .folderAccess, .chaining, .conversation],
                id: \.self
            ) { sec in
                SidebarNavItem(label: sec.label, isSelected: selection == sec) { selection = sec }
            }

            SidebarSectionHeader(label: "Danger Zone")
            SidebarNavItem(
                label: ChannelSettingsSection.deleteChannel.label,
                isSelected: selection == .deleteChannel,
                isDanger: true
            ) { selection = .deleteChannel }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var channelContent: some View {
        switch selection {
        case .overview:
            SettingsPage(title: "Overview") { overviewContent }
        case .members:
            SettingsPage(title: "Members") { membersContent }
        case .folderAccess:
            SettingsPage(title: "Folder Access") { channelFoldersContent }
        case .chaining:
            SettingsPage(title: "Agent Chaining") { chainingContent }
        case .conversation:
            SettingsPage(title: "Conversation") { conversationContent }
        case .deleteChannel:
            SettingsPage(title: "Danger Zone") { channelDangerContent }
        }
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            KinField("Channel Name", placeholder: "#channel-name", text: $draft.name)
            KinField("Topic", placeholder: "What is this channel for?", text: $draft.topic)
        }
    }

    private var membersContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Choose which agents participate in this channel.")
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textSecondary)

            ForEach(store.activeAgents) { agent in
                let isMember = draft.memberAgentIds.contains(agent.id)
                Button {
                    if isMember {
                        draft.memberAgentIds.removeAll { $0 == agent.id }
                    } else {
                        draft.memberAgentIds.append(agent.id)
                    }
                } label: {
                    HStack(spacing: 10) {
                        AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 28, avatarPath: agent.avatarPath)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(agent.name)
                                .font(Kin.inter(13, weight: .medium))
                                .foregroundStyle(Kin.textPrimary)
                            Text(agent.role)
                                .font(Kin.inter(11))
                                .foregroundStyle(Kin.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: isMember ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(isMember ? Kin.accent : Kin.textTertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(isMember ? Kin.surface : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var channelFoldersContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Folders accessible to all agents in this channel.")
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textSecondary)

            if draft.folderPaths.isEmpty {
                Text("No folders granted")
                    .font(Kin.inter(13))
                    .foregroundStyle(Kin.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(draft.folderPaths, id: \.self) { path in
                        HStack {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundStyle(Kin.textTertiary)
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Kin.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                draft.folderPaths.removeAll { $0 == path }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Kin.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            Button("Add Folder…") { pickChannelFolder() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private func pickChannelFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !draft.folderPaths.contains(url.path) { draft.folderPaths.append(url.path) }
        }
    }

    @ViewBuilder
    private var chainingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: $draft.chainingEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enable auto-chaining")
                        .font(Kin.inter(13, weight: .medium))
                        .foregroundStyle(Kin.textPrimary)
                    Text("Agents may invoke each other after responding.")
                        .font(Kin.inter(12))
                        .foregroundStyle(Kin.textSecondary)
                }
            }
            .toggleStyle(.switch)

            if draft.chainingEnabled {
                Rectangle().fill(Kin.border).frame(height: 1)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Trigger Rules")
                        .font(Kin.inter(14, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    Text("Define which agents invoke which after responding.")
                        .font(Kin.inter(12))
                        .foregroundStyle(Kin.textSecondary)

                    ForEach(draft.triggerRules) { rule in
                        let afterName = store.agents.first { $0.id == rule.afterAgentId }?.name ?? rule.afterAgentId
                        let invokeName = store.agents.first { $0.id == rule.invokeAgentId }?.name ?? rule.invokeAgentId
                        HStack {
                            Text("After \(afterName) → \(invokeName)")
                                .font(Kin.inter(12))
                                .foregroundStyle(Kin.textSecondary)
                            Spacer()
                            Button {
                                draft.triggerRules.removeAll { $0.id == rule.id }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Kin.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 6))
                    }

                    TriggerRuleAdder(
                        agents: store.activeAgents.filter { draft.memberAgentIds.contains($0.id) }
                    ) { rule in
                        draft.triggerRules.append(rule)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var conversationContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Everything sent in this channel so far — user messages, agent replies, tool calls, and errors.")
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textSecondary)

            HStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Kin.textSecondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(runner.messages.count) message\(runner.messages.count == 1 ? "" : "s")")
                        .font(Kin.inter(13, weight: .medium))
                        .foregroundStyle(Kin.textPrimary)
                    Text("Clearing stops any running agents and removes the saved conversation file.")
                        .font(Kin.inter(12))
                        .foregroundStyle(Kin.textSecondary)
                }

                Spacer()

                Button("Clear Conversation") { showClearConfirm = true }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red.opacity(0.85))
                    .controlSize(.small)
                    .disabled(runner.messages.isEmpty)
                    .confirmationDialog(
                        "Clear conversation in #\(channel.name)?",
                        isPresented: $showClearConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Clear", role: .destructive) { runner.clearHistory() }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("All messages will be deleted and running agents stopped. The channel itself and its settings will remain.")
                    }
            }
            .padding(16)
            .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var channelDangerContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Delete Channel")
                .font(Kin.inter(16, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)
            Text("Permanently deletes this channel and all its messages. This cannot be undone.")
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textSecondary)
            Button("Delete Channel") { showDeleteConfirm = true }
                .buttonStyle(.bordered)
                .foregroundStyle(.red.opacity(0.85))
                .controlSize(.regular)
                .confirmationDialog(
                    "Delete #\(channel.name)?",
                    isPresented: $showDeleteConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        store.deleteChannel(channel)
                        isPresented = false
                    }
                    Button("Cancel", role: .cancel) {}
                }
        }
        .padding(16)
        .background(Color.red.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.2), lineWidth: 1))
    }
}

// MARK: - Trigger rule adder

private struct TriggerRuleAdder: View {
    let agents: [AgentConfig]
    let onAdd: (TriggerRule) -> Void
    @State private var afterId = ""
    @State private var invokeId = ""

    var body: some View {
        HStack(spacing: 8) {
            Picker("After", selection: $afterId) {
                Text("After…").tag("")
                ForEach(agents) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu).labelsHidden().font(Kin.inter(11)).frame(maxWidth: .infinity)
            Text("→").foregroundStyle(Kin.textSecondary).font(Kin.inter(11))
            Picker("Invoke", selection: $invokeId) {
                Text("invoke…").tag("")
                ForEach(agents) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu).labelsHidden().font(Kin.inter(11)).frame(maxWidth: .infinity)
            Button("Add") {
                guard !afterId.isEmpty, !invokeId.isEmpty, afterId != invokeId else { return }
                onAdd(TriggerRule(afterAgentId: afterId, invokeAgentId: invokeId))
                afterId = ""; invokeId = ""
            }
            .buttonStyle(.borderedProminent).tint(Kin.accent).controlSize(.small)
            .disabled(afterId.isEmpty || invokeId.isEmpty || afterId == invokeId)
        }
    }
}
