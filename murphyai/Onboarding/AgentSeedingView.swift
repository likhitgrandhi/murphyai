import SwiftUI

struct AgentSeedingView: View {
    let workspace: KinWorkspace
    let onComplete: () -> Void

    @State private var selected: Set<String> = Set(AgentConfig.defaultAgents.prefix(4).map(\.id))
    @State private var saving = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("Meet your agents")
                    .font(Kin.inter(28, weight: .bold))
                    .foregroundStyle(Kin.textPrimary)
                Text("Select the AI agents to add to **\(workspace.name)**. You can add or remove them later.")
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 500)
            }
            .padding(.bottom, 32)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(AgentConfig.defaultAgents) { agent in
                    AgentSeedCard(
                        agent: agent,
                        isSelected: selected.contains(agent.id),
                        onToggle: { toggle(agent.id) }
                    )
                }
            }
            .frame(width: 620)
            .padding(.bottom, 32)

            HStack(spacing: 12) {
                Button("Skip") {
                    save(agents: [])
                }
                .buttonStyle(KinSecondaryButtonStyle())

                Button(action: { save(agents: AgentConfig.defaultAgents.filter { selected.contains($0.id) }) }) {
                    HStack {
                        if saving { ProgressView().scaleEffect(0.7).tint(.white) }
                        Text(saving ? "Saving…" : "Add \(selected.count) agent\(selected.count == 1 ? "" : "s")")
                            .font(Kin.inter(14, weight: .semibold))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 9)
                    .background(selected.isEmpty ? Kin.accent.opacity(0.4) : Kin.accent)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty || saving)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Kin.bg)
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func save(agents: [AgentConfig]) {
        saving = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        let baseDir = home.appendingPathComponent(".kin/workspaces/\(workspace.id.uuidString)", isDirectory: true)
        for agent in agents {
            let agentDir = baseDir.appendingPathComponent(agent.id, isDirectory: true)
            try? FileManager.default.createDirectory(at: agentDir, withIntermediateDirectories: true)
            let url = agentDir.appendingPathComponent("config.json")
            if let data = try? JSONEncoder().encode(agent) {
                try? data.write(to: url)
            }
        }
        saving = false
        onComplete()
    }
}

private struct AgentSeedCard: View {
    let agent: AgentConfig
    let isSelected: Bool
    let onToggle: () -> Void

    private var tint: Color {
        Color(hex: agent.tint) ?? Kin.accent
    }

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: agent.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(Kin.inter(13, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    Text(agent.role)
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? Kin.accent : Kin.textQuaternary)
            }
            .padding(14)
            .background(isSelected ? Kin.accent.opacity(0.06) : Kin.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Kin.accent.opacity(0.4) : Kin.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
