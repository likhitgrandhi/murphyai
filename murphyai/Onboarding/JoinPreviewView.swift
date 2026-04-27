import SwiftUI

// Shown after the user enters an invite code or taps a deep link.
// Displays workspace details and a Join button before anything is committed.
struct JoinPreviewView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    let preview: InvitePreview
    let code: String
    let onJoined: (KinWorkspace) -> Void
    let onCancel: () -> Void

    @State private var loading = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("You've been invited")
                    .font(Kin.inter(28, weight: .bold))
                    .foregroundStyle(Kin.textPrimary)
                Text("Review the workspace before joining.")
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textTertiary)
            }
            .padding(.bottom, 32)

            // Workspace card
            VStack(spacing: 0) {
                // Header strip
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Kin.accent.opacity(0.15))
                            .frame(width: 48, height: 48)
                        Text(preview.workspaceName.prefix(2).uppercased())
                            .font(Kin.inter(18, weight: .bold))
                            .foregroundStyle(Kin.accent)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(preview.workspaceName)
                            .font(Kin.inter(17, weight: .semibold))
                            .foregroundStyle(Kin.textPrimary)
                        Text("kin.ai/\(preview.workspaceSlug)")
                            .font(Kin.inter(12))
                            .foregroundStyle(Kin.textTertiary)
                    }
                    Spacer()
                    if preview.alreadyMember {
                        Label("Already joined", systemImage: "checkmark.circle.fill")
                            .font(Kin.inter(12, weight: .medium))
                            .foregroundStyle(Kin.statusOnline)
                    }
                }
                .padding(20)

                Divider().background(Kin.border)

                // Stats row
                HStack(spacing: 0) {
                    stat(value: "\(preview.memberCount)", label: preview.memberCount == 1 ? "member" : "members")
                    Divider().frame(height: 32).background(Kin.border)
                    stat(value: preview.invitedByName, label: "invited by")
                    Divider().frame(height: 32).background(Kin.border)
                    stat(value: expiryLabel, label: "invite expires")
                }
                .padding(.vertical, 16)
            }
            .background(Kin.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Kin.border, lineWidth: 1))
            .frame(width: 440)

            // Error
            if let err = error {
                Text(err)
                    .font(Kin.inter(12))
                    .foregroundStyle(Kin.statusOffline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
                    .padding(.top, 12)
            }

            // Email-gate notice
            if preview.emailGated {
                Label("This invite is for a specific email address.", systemImage: "envelope.badge.fill")
                    .font(Kin.inter(12))
                    .foregroundStyle(Kin.textTertiary)
                    .padding(.top, 10)
            }

            // Actions
            HStack(spacing: 12) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(KinSecondaryButtonStyle())

                if preview.alreadyMember {
                    Button("Open workspace") {
                        Task { await openExistingWorkspace() }
                    }
                    .buttonStyle(KinPrimaryButtonStyle(loading: loading))
                } else {
                    Button(action: { Task { await join() } }) {
                        HStack {
                            if loading { ProgressView().scaleEffect(0.7).tint(.white) }
                            Text(loading ? "Joining…" : "Join \(preview.workspaceName)")
                                .font(Kin.inter(14, weight: .semibold))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Kin.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(loading)
                }
            }
            .padding(.top, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Kin.bg)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(Kin.inter(14, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)
                .lineLimit(1)
            Text(label)
                .font(Kin.inter(11))
                .foregroundStyle(Kin.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var expiryLabel: String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: preview.expiresAt).day ?? 0
        if days <= 0 { return "today" }
        if days == 1 { return "tomorrow" }
        return "in \(days) days"
    }

    private func join() async {
        loading = true
        error = nil
        defer { loading = false }
        do {
            let ws = try await workspaceStore.joinByCode(code)
            onJoined(ws)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func openExistingWorkspace() async {
        loading = true
        defer { loading = false }
        // Workspace already joined — just fetch it and navigate
        if let ws = workspaceStore.workspaces.first(where: { $0.id == preview.workspaceId }) {
            workspaceStore.select(ws)
            onJoined(ws)
            return
        }
        // Not in local list yet (e.g. after fresh launch) — refresh then navigate
        await workspaceStore.refresh()
        if let ws = workspaceStore.workspaces.first(where: { $0.id == preview.workspaceId }) {
            workspaceStore.select(ws)
            onJoined(ws)
        }
    }
}

struct KinPrimaryButtonStyle: ButtonStyle {
    var loading: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Kin.inter(14, weight: .semibold))
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(loading ? Kin.accent.opacity(0.6) : Kin.accent)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}
