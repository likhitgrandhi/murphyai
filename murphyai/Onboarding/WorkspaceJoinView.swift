import SwiftUI

// Step 1 of joining: enter the code and fetch a preview.
// Actual join happens in JoinPreviewView after the user sees the workspace card.
struct WorkspaceJoinView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    let onPreviewed: (InvitePreview, String) -> Void  // preview + raw code
    let onBack: () -> Void

    @State private var code = ""
    @State private var loading = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("Join a workspace")
                    .font(Kin.inter(28, weight: .bold))
                    .foregroundStyle(Kin.textPrimary)
                Text("Paste the invite code or link you received.")
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textTertiary)
            }
            .padding(.bottom, 40)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Invite code or link")
                        .font(Kin.inter(12, weight: .medium))
                        .foregroundStyle(Kin.textSecondary)

                    TextField("e.g. abc-def-ghi  or  kin://join?code=…", text: $code)
                        .textFieldStyle(.plain)
                        .font(Kin.inter(14))
                        .foregroundStyle(Kin.textPrimary)
                        .focused($focused)
                        .onSubmit { Task { await preview() } }
                        .onChange(of: code) { _, new in
                            // Strip the kin:// prefix if user pastes a full link
                            if new.lowercased().hasPrefix("kin://join?code=") {
                                code = String(new.dropFirst("kin://join?code=".count))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Kin.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(focused ? Kin.accent.opacity(0.5) : Kin.border, lineWidth: 1)
                        )
                }

                if let err = error {
                    Text(err)
                        .font(Kin.inter(12))
                        .foregroundStyle(Kin.statusOffline)
                }

                HStack(spacing: 10) {
                    Button("Back") { onBack() }
                        .buttonStyle(KinSecondaryButtonStyle())

                    Button(action: { Task { await preview() } }) {
                        HStack {
                            if loading { ProgressView().scaleEffect(0.7).tint(.white) }
                            Text(loading ? "Looking up…" : "Preview workspace")
                                .font(Kin.inter(14, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(canSubmit ? Kin.accent : Kin.accent.opacity(0.4))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || loading)
                }
            }
            .padding(24)
            .background(Kin.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(width: 400)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Kin.bg)
        .onAppear { focused = true }
    }

    private var canSubmit: Bool { code.trimmingCharacters(in: .whitespaces).count >= 4 }

    private func preview() async {
        guard canSubmit else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let p = try await workspaceStore.previewInvite(code: code)
            onPreviewed(p, code.trimmingCharacters(in: .whitespaces))
        } catch {
            self.error = error.localizedDescription
        }
    }
}
