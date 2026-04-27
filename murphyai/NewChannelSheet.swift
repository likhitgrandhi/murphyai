import SwiftUI
import Supabase

// Unified channel creation. The Private toggle picks the scope:
//   - Off (default): a workspace channel — visible to selected teammates and
//     the agents they've shared. Personal agents picked here are auto-promoted
//     to team agents on create.
//   - On: a just-me channel — local-only, agents only, can use folder paths.
struct NewChannelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AgentStore.self) private var agentStore
    @Environment(SharedChannelStore.self) private var sharedChannels
    @Environment(AgentRoster.self) private var roster
    @Environment(SessionStore.self) private var session

    enum CreatedChannel {
        case shared(ServerChannel)
        case personal(Channel)
    }

    var onCreated: ((CreatedChannel) -> Void)? = nil

    @State private var name = ""
    @State private var topic = ""
    @State private var isPrivate = false
    @State private var selectedHumanIds: Set<UUID> = []
    @State private var selectedAgentKeys: Set<String> = []
    @State private var folderPaths: [String] = []
    @State private var creating = false
    @State private var errorMessage: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        !creating && !trimmedName.isEmpty
    }

    private var workspaceMembers: [WorkspaceMember] {
        let me = session.currentUser?.id
        return sharedChannels.membersById.values
            .filter { $0.userId != me }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private var agentItems: [AgentPickerItem] {
        var items: [AgentPickerItem] = agentStore.activeAgents.map { .personal($0) }
        let personalSlugs = Set(agentStore.activeAgents.map { $0.id.lowercased() })
        for team in roster.allAgents where !personalSlugs.contains(team.slug.lowercased()) {
            items.append(.team(team))
        }
        return items.sorted { $0.displayName.lowercased() < $1.displayName.lowercased() }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().background(Kin.border)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    nameField
                    topicField
                    privateToggle
                    if !isPrivate && !workspaceMembers.isEmpty {
                        membersSection
                    }
                    agentsSection
                    if isPrivate {
                        privateHint
                    }
                    if let err = errorMessage {
                        Text(err).font(Kin.inter(11)).foregroundStyle(Kin.statusOffline)
                    }
                }
                .padding(20)
            }
            footer
        }
        .frame(width: 500, height: 640)
        .background(Kin.bg)
    }

    // MARK: - Header / footer

    private var titleBar: some View {
        HStack {
            Text("New channel")
                .font(Kin.inter(15, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Kin.textTertiary)
                    .frame(width: 22, height: 22)
                    .background(Kin.inputBg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Text("Cancel")
                    .font(Kin.inter(12, weight: .semibold))
                    .foregroundStyle(Kin.textSecondary)
                    .padding(.horizontal, 14).padding(.vertical, 7)
            }
            .buttonStyle(.plain)
            Button { create() } label: {
                Text(creating ? "Creating…" : "Create")
                    .font(Kin.inter(12, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(canCreate ? Kin.accent : Kin.textQuaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
            .disabled(!canCreate)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Kin.border).frame(height: 1) }
    }

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Name")
            TextField("design-reviews", text: $name)
                .textFieldStyle(.plain)
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Kin.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Kin.border, lineWidth: 1))
        }
    }

    private var topicField: some View {
        VStack(alignment: .leading, spacing: 6) {
            label("Topic (optional)")
            TextField("What this channel is for", text: $topic)
                .textFieldStyle(.plain)
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(Kin.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Kin.border, lineWidth: 1))
        }
    }

    private var privateToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $isPrivate) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Private")
                        .font(Kin.inter(13, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    Text(isPrivate
                         ? "Only you and the agents you add — local to this Mac, can use folders."
                         : "Visible to selected teammates and their agents.")
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textTertiary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    private var privateHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(Kin.textTertiary)
            Text("Messages stay on this Mac. Folder access can be granted to agents in this channel.")
                .font(Kin.inter(10))
                .foregroundStyle(Kin.textTertiary)
        }
    }

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("People")
            VStack(spacing: 0) {
                ForEach(workspaceMembers) { m in
                    pickerRow(
                        title: m.name,
                        subtitle: m.email,
                        selected: selectedHumanIds.contains(m.userId),
                        leading: { humanAvatar(m) }
                    ) { toggleHuman(m.userId) }
                    if m.id != workspaceMembers.last?.id {
                        Divider().background(Kin.border)
                    }
                }
            }
            .background(Kin.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Kin.border, lineWidth: 1))
        }
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            label("Agents")
            if agentItems.isEmpty {
                Text("Create an agent first.")
                    .font(Kin.inter(11))
                    .foregroundStyle(Kin.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(agentItems) { item in
                        pickerRow(
                            title: item.displayName,
                            subtitle: "@\(item.slug)",
                            selected: selectedAgentKeys.contains(item.id),
                            leading: { agentAvatar(item) }
                        ) { toggleAgent(item.id) }
                        if item.id != agentItems.last?.id {
                            Divider().background(Kin.border)
                        }
                    }
                }
                .background(Kin.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Kin.border, lineWidth: 1))
            }
        }
    }

    // MARK: - Row primitives

    @ViewBuilder
    private func humanAvatar(_ m: WorkspaceMember) -> some View {
        ZStack {
            Circle().fill(Kin.accent.opacity(0.18)).frame(width: 28, height: 28)
            Text(m.initials)
                .font(Kin.inter(10, weight: .bold))
                .foregroundStyle(Kin.accent)
        }
    }

    @ViewBuilder
    private func agentAvatar(_ item: AgentPickerItem) -> some View {
        switch item {
        case .personal(let a):
            AgentAvatarCircle(name: a.name, tint: a.tint, size: 28, avatarPath: a.avatarPath)
        case .team(let a):
            ZStack {
                Circle()
                    .fill((Color(hex: a.avatarTint ?? "") ?? Kin.accent).opacity(0.18))
                    .frame(width: 28, height: 28)
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: a.avatarTint ?? "") ?? Kin.accent)
            }
        }
    }

    private func pickerRow<L: View>(
        title: String, subtitle: String, selected: Bool,
        @ViewBuilder leading: () -> L,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leading()
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Kin.inter(12, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    Text(subtitle)
                        .font(Kin.inter(10))
                        .foregroundStyle(Kin.textTertiary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(selected ? Kin.accent : Kin.textQuaternary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func label(_ s: String) -> some View {
        Text(s)
            .font(Kin.inter(11, weight: .semibold))
            .foregroundStyle(Kin.textSecondary)
            .tracking(0.5)
    }

    // MARK: - Selection toggles

    private func toggleHuman(_ id: UUID) {
        if selectedHumanIds.contains(id) { selectedHumanIds.remove(id) }
        else { selectedHumanIds.insert(id) }
    }

    private func toggleAgent(_ key: String) {
        if selectedAgentKeys.contains(key) { selectedAgentKeys.remove(key) }
        else { selectedAgentKeys.insert(key) }
    }

    // MARK: - Create

    private func create() {
        guard canCreate else { return }
        creating = true
        errorMessage = nil
        Task {
            defer { creating = false }
            do {
                if isPrivate {
                    try await createPrivate()
                } else {
                    try await createShared()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createPrivate() async throws {
        // Local channel — only personal agents make sense here. Team agents
        // would need to be claimed remotely; private channels are local-only.
        let memberAgentIds: [String] = selectedAgentKeys.compactMap { key in
            guard key.hasPrefix("p:") else { return nil }
            return String(key.dropFirst(2))
        }
        let slug = trimmedName.lowercased().replacingOccurrences(of: " ", with: "-")
        let channel = Channel(
            id: UUID().uuidString,
            name: slug,
            topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
            memberAgentIds: memberAgentIds,
            folderPaths: folderPaths
        )
        agentStore.saveChannel(channel)
        onCreated?(.personal(channel))
        dismiss()
    }

    private func createShared() async throws {
        let topicTrimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let ch = try await sharedChannels.createChannel(
            name: trimmedName,
            topic: topicTrimmed.isEmpty ? nil : topicTrimmed
        )

        // Add humans (best-effort — partial failures don't block channel creation)
        for uid in selectedHumanIds {
            do {
                try await kinSupabase
                    .rpc("add_to_channel", params: AddToChannelParams(channelId: ch.id, userId: uid))
                    .execute()
            } catch {
                print("[NewChannelSheet] add_to_channel failed:", error)
            }
        }

        // Add/promote agents
        for key in selectedAgentKeys {
            do {
                if key.hasPrefix("p:") {
                    let pid = String(key.dropFirst(2))
                    if let personal = agentStore.activeAgents.first(where: { $0.id == pid }) {
                        try await roster.shareAndAdd(personal: personal, channelId: ch.id)
                    }
                } else if key.hasPrefix("t:"),
                          let uuid = UUID(uuidString: String(key.dropFirst(2))) {
                    try await roster.addToChannel(agentId: uuid, channelId: ch.id)
                }
            } catch {
                print("[NewChannelSheet] add agent failed:", error)
            }
        }

        onCreated?(.shared(ch))
        dismiss()
    }
}

// MARK: - Picker item

private enum AgentPickerItem: Identifiable {
    case personal(AgentConfig)
    case team(TeamAgent)

    var id: String {
        switch self {
        case .personal(let a): return "p:\(a.id)"
        case .team(let a):     return "t:\(a.id.uuidString)"
        }
    }
    var displayName: String {
        switch self {
        case .personal(let a): return a.name
        case .team(let a):     return a.displayName
        }
    }
    var slug: String {
        switch self {
        case .personal(let a): return a.id
        case .team(let a):     return a.slug
        }
    }
}

private struct AddToChannelParams: Encodable, Sendable {
    let channelId: UUID
    let userId: UUID
    enum CodingKeys: String, CodingKey {
        case channelId = "p_channel_id"
        case userId    = "p_user_id"
    }
}
