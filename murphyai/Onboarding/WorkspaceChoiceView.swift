import SwiftUI

struct WorkspaceChoiceView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    enum Action { case create, join }
    let onSelect: (Action) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("Kin")
                    .font(Kin.inter(48, weight: .bold))
                    .foregroundStyle(Kin.textPrimary)
                Text("Welcome! Set up your workspace to get started.")
                    .font(Kin.inter(14, weight: .regular))
                    .foregroundStyle(Kin.textTertiary)
            }
            .padding(.bottom, 24)

            if let err = workspaceStore.error {
                VStack(spacing: 10) {
                    Text("Couldn't load your workspaces: \(err)")
                        .font(Kin.inter(12))
                        .foregroundStyle(Kin.statusOffline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 500)
                    Button {
                        Task { await workspaceStore.refresh() }
                    } label: {
                        Text("Retry")
                            .font(Kin.inter(12, weight: .semibold))
                            .foregroundStyle(Kin.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .overlay(Capsule().strokeBorder(Kin.accent, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(workspaceStore.isLoading)
                }
                .padding(.bottom, 16)
            }

            HStack(spacing: 16) {
                ChoiceCard(
                    icon: "plus.square.fill",
                    title: "Create a workspace",
                    subtitle: "Start fresh for you or your team",
                    action: { onSelect(.create) }
                )
                ChoiceCard(
                    icon: "person.badge.key.fill",
                    title: "Join a workspace",
                    subtitle: "You have an invite code",
                    action: { onSelect(.join) }
                )
            }
            .frame(width: 600)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Kin.bg)
    }
}

private struct ChoiceCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundStyle(Kin.accent)
                VStack(spacing: 6) {
                    Text(title)
                        .font(Kin.inter(15, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    Text(subtitle)
                        .font(Kin.inter(12))
                        .foregroundStyle(Kin.textTertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(hovering ? Kin.surface.opacity(1.0) : Kin.surface.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(hovering ? Kin.accent.opacity(0.5) : Kin.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
