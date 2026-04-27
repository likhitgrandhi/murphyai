import SwiftUI

struct WorkspaceCreateView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    let onCreated: (KinWorkspace) -> Void
    let onBack: () -> Void

    @State private var name = ""
    @State private var loading = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 8) {
                Text("Name your workspace")
                    .font(Kin.inter(28, weight: .bold))
                    .foregroundStyle(Kin.textPrimary)
                Text("You can always rename it later.")
                    .font(Kin.inter(14))
                    .foregroundStyle(Kin.textTertiary)
            }
            .padding(.bottom, 40)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Workspace name")
                        .font(Kin.inter(12, weight: .medium))
                        .foregroundStyle(Kin.textSecondary)

                    TextField("e.g. Acme Corp", text: $name)
                        .textFieldStyle(.plain)
                        .font(Kin.inter(14))
                        .foregroundStyle(Kin.textPrimary)
                        .focused($focused)
                        .onSubmit { Task { await create() } }
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

                    Button(action: { Task { await create() } }) {
                        HStack {
                            if loading { ProgressView().scaleEffect(0.7).tint(.white) }
                            Text(loading ? "Creating…" : "Create workspace")
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

    private var canSubmit: Bool { name.trimmingCharacters(in: .whitespaces).count >= 2 }

    private func create() async {
        guard canSubmit else { return }
        loading = true
        error = nil
        defer { loading = false }
        do {
            let ws = try await workspaceStore.create(name: name.trimmingCharacters(in: .whitespaces))
            onCreated(ws)
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct KinSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Kin.inter(14, weight: .medium))
            .foregroundStyle(Kin.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Kin.inputBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Kin.border, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
