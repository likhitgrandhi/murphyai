import SwiftUI

// Picks an agent (personal or team) and adds it to a channel.
// Personal agents are auto-promoted to team agents on add — sharing IS the
// promotion event. Folder access and local memory don't carry over; the team
// copy gets only name + slug + system prompt.
struct AddAgentToChannelSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AgentRoster.self) private var roster
    @Environment(AgentStore.self) private var agentStore

    let channel: ServerChannel
    var onAdded: (() -> Void)? = nil

    @State private var adding: String?      // agent id being added
    @State private var errorMessage: String?

    private var teamAgentsAvailable: [TeamAgent] {
        let inChannel = Set(roster.agents(in: channel.id).map(\.id))
        return roster.allAgents.filter { !inChannel.contains($0.id) }
    }

    // Personal agents whose slug isn't already represented in this channel
    // (either as a team agent or already-promoted version).
    private var personalAgentsAvailable: [AgentConfig] {
        let teamSlugs = Set(roster.allAgents.map { $0.slug.lowercased() })
        let inChannelSlugs = Set(roster.agents(in: channel.id).map { $0.slug.lowercased() })
        return agentStore.activeAgents.filter { agent in
            let slug = agent.id.lowercased()
            // Hide if already promoted AND already in channel
            if teamSlugs.contains(slug) && inChannelSlugs.contains(slug) { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().background(Kin.border)
            content
        }
        .frame(width: 420, height: 540)
        .background(Kin.bg)
        .task { await roster.refreshChannelAgents(for: channel.id) }
    }

    private var titleBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add agent to #\(channel.displayName)")
                    .font(Kin.inter(15, weight: .semibold))
                    .foregroundStyle(Kin.textPrimary)
                Text("Personal agents will be shared with the team when added")
                    .font(Kin.inter(11))
                    .foregroundStyle(Kin.textTertiary)
            }
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

    @ViewBuilder
    private var content: some View {
        if teamAgentsAvailable.isEmpty && personalAgentsAvailable.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !teamAgentsAvailable.isEmpty {
                        sectionHeader("TEAM AGENTS")
                        ForEach(teamAgentsAvailable) { agent in
                            teamAgentRow(agent)
                        }
                    }
                    if !personalAgentsAvailable.isEmpty {
                        sectionHeader("YOUR AGENTS")
                        ForEach(personalAgentsAvailable) { agent in
                            personalAgentRow(agent)
                        }
                    }
                    if let err = errorMessage {
                        Text(err)
                            .font(Kin.inter(11))
                            .foregroundStyle(Kin.statusOffline)
                            .padding(14)
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No agents available to add")
                .font(Kin.inter(13, weight: .semibold))
                .foregroundStyle(Kin.textSecondary)
            Text("Create a personal agent first, then come back to share it.")
                .font(Kin.inter(12))
                .foregroundStyle(Kin.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 30)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Kin.inter(10, weight: .semibold))
            .foregroundStyle(Kin.textTertiary)
            .tracking(0.5)
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 4)
    }

    private func teamAgentRow(_ agent: TeamAgent) -> some View {
        let tint = Color(hex: agent.avatarTint ?? "") ?? Kin.accent
        return Button { addTeamAgent(agent) } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle().fill(tint.opacity(0.18)).frame(width: 32, height: 32)
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.displayName)
                        .font(Kin.inter(13, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    Text("@\(agent.slug)")
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textTertiary)
                }
                Spacer()
                trailingIndicator(forKey: agent.id.uuidString)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(adding != nil)
    }

    private func personalAgentRow(_ agent: AgentConfig) -> some View {
        let tint = Color(hex: agent.tint) ?? Kin.accent
        return Button { shareAndAddPersonal(agent) } label: {
            HStack(spacing: 10) {
                AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 32, avatarPath: agent.avatarPath)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(agent.name)
                            .font(Kin.inter(13, weight: .semibold))
                            .foregroundStyle(Kin.textPrimary)
                        Text("Share")
                            .font(Kin.inter(9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(tint.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(agent.role.isEmpty ? "@\(agent.id)" : agent.role)
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                trailingIndicator(forKey: agent.id)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(adding != nil)
    }

    @ViewBuilder
    private func trailingIndicator(forKey key: String) -> some View {
        if adding == key {
            ProgressView().controlSize(.small)
        } else {
            Image(systemName: "plus.circle")
                .font(.system(size: 16))
                .foregroundStyle(Kin.accent)
        }
    }

    // MARK: - Actions

    private func addTeamAgent(_ agent: TeamAgent) {
        guard adding == nil else { return }
        adding = agent.id.uuidString
        errorMessage = nil
        Task {
            defer { adding = nil }
            do {
                try await roster.addToChannel(agentId: agent.id, channelId: channel.id)
                onAdded?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func shareAndAddPersonal(_ agent: AgentConfig) {
        guard adding == nil else { return }
        adding = agent.id
        errorMessage = nil
        Task {
            defer { adding = nil }
            do {
                try await roster.shareAndAdd(personal: agent, channelId: channel.id)
                onAdded?()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
