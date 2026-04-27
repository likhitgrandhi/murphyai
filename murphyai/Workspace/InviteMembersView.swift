import SwiftUI
import AppKit

struct InviteMembersView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var generating = false
    @State private var generateError: String?
    @State private var invitations: [KinInvitation] = []
    @State private var loadingInvites = false
    @State private var invitesError: String?
    @State private var copiedCode: String?
    @FocusState private var emailFocused: Bool

    private var workspace: KinWorkspace? { workspaceStore.current }

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Invite members")
                    .font(Kin.inter(17, weight: .semibold))
                    .foregroundStyle(Kin.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Kin.textTertiary)
                        .frame(width: 24, height: 24)
                        .background(Kin.inputBg)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider().background(Kin.border)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    generateSection
                    if let err = invitesError {
                        Text(err)
                            .font(Kin.inter(11))
                            .foregroundStyle(Kin.statusOffline)
                    }
                    if !invitations.isEmpty {
                        activeInvitesSection
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 500, height: 540)
        .background(Kin.bg)
        .task { await loadInvitations() }
    }

    // MARK: - Generate section

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Generate invite link")
                .font(Kin.inter(13, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)

            Text("Anyone with the link can join **\(workspace?.name ?? "this workspace")**. Optionally restrict it to a specific email address.")
                .font(Kin.inter(12))
                .foregroundStyle(Kin.textTertiary)

            VStack(alignment: .leading, spacing: 6) {
                Text("Email address (optional)")
                    .font(Kin.inter(12, weight: .medium))
                    .foregroundStyle(Kin.textSecondary)

                HStack(spacing: 8) {
                    TextField("teammate@company.com", text: $email)
                        .textFieldStyle(.plain)
                        .font(Kin.inter(13))
                        .foregroundStyle(Kin.textPrimary)
                        .focused($emailFocused)
                        .onSubmit { Task { await generate() } }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Kin.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(emailFocused ? Kin.accent.opacity(0.5) : Kin.border, lineWidth: 1)
                        )

                    Button(action: { Task { await generate() } }) {
                        HStack(spacing: 4) {
                            if generating { ProgressView().scaleEffect(0.65).tint(.white) }
                            Text(generating ? "Creating…" : "Generate link")
                                .font(Kin.inter(13, weight: .semibold))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(generating ? Kin.accent.opacity(0.6) : Kin.accent)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .disabled(generating)
                }
            }

            if let err = generateError {
                Text(err)
                    .font(Kin.inter(11))
                    .foregroundStyle(Kin.statusOffline)
            }
        }
    }

    // MARK: - Active invites section

    private var activeInvitesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your invite links")
                    .font(Kin.inter(13, weight: .semibold))
                    .foregroundStyle(Kin.textPrimary)
                Spacer()
                if loadingInvites {
                    ProgressView().scaleEffect(0.6)
                }
            }

            VStack(spacing: 6) {
                ForEach(invitations) { inv in
                    InviteRow(inv: inv, copiedCode: $copiedCode) {
                        copy(inv.code)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func generate() async {
        guard let ws = workspace else { return }
        generating = true
        generateError = nil
        defer { generating = false }
        do {
            let inv = try await workspaceStore.createInvitation(
                workspaceId: ws.id,
                email: email.trimmingCharacters(in: .whitespaces).nilIfEmpty
            )
            invitations.insert(inv, at: 0)
            email = ""
            copy(inv.code)
        } catch {
            generateError = error.localizedDescription
        }
    }

    private func loadInvitations() async {
        guard let ws = workspace else { return }
        loadingInvites = true
        invitesError = nil
        defer { loadingInvites = false }
        do {
            invitations = try await workspaceStore.fetchInvitations(for: ws.id)
        } catch {
            // Surface the failure — previously swallowed, which made the list
            // look empty when the actual cause was a permission/network error
            // and users would re-invite, creating duplicates.
            invitesError = error.localizedDescription
            print("[InviteMembersView] fetchInvitations failed:", error)
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedCode = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if copiedCode == text { copiedCode = nil }
        }
    }
}

// MARK: - Invite row

private struct InviteRow: View {
    let inv: KinInvitation
    @Binding var copiedCode: String?
    let onCopy: () -> Void  // copies the code

    private var isCopied: Bool { copiedCode == inv.code }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                // Code displayed large and readable
                HStack(spacing: 8) {
                    Text(inv.code)
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(inv.isActive ? Kin.textPrimary : Kin.textTertiary)

                    if inv.isRedeemed {
                        badge("Used", color: Kin.textQuaternary)
                    } else if inv.isExpired {
                        badge("Expired", color: Kin.statusOffline)
                    } else {
                        badge("Active", color: Kin.statusOnline)
                    }
                }

                HStack(spacing: 8) {
                    if let email = inv.email {
                        Label(email, systemImage: "envelope")
                            .font(Kin.inter(10))
                            .foregroundStyle(Kin.textTertiary)
                    }
                    Label(expiryText, systemImage: "clock")
                        .font(Kin.inter(10))
                        .foregroundStyle(inv.isExpired ? Kin.statusOffline : Kin.textTertiary)
                }
            }

            Spacer()

            if inv.isActive {
                Button(action: onCopy) {
                    Label(isCopied ? "Copied!" : "Copy code", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                        .font(Kin.inter(11, weight: .medium))
                        .foregroundStyle(isCopied ? Kin.statusOnline : Kin.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isCopied ? Kin.statusOnline.opacity(0.1) : Kin.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Kin.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Kin.border, lineWidth: 1))
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(Kin.inter(9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private var expiryText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        if inv.isExpired { return "Expired \(formatter.localizedString(for: inv.expiresAt, relativeTo: Date()))" }
        return "Expires \(formatter.localizedString(for: inv.expiresAt, relativeTo: Date()))"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
