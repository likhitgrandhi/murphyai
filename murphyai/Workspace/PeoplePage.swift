import SwiftUI

struct PeoplePage: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    @Environment(SessionStore.self) private var session

    @State private var members: [WorkspaceMember] = []
    @State private var invitations: [KinInvitation] = []
    @State private var loading = true
    @State private var membersError: String?
    @State private var invitesError: String?
    @State private var showInviteSheet = false
    @State private var tab: Tab = .members

    private enum Tab: Hashable { case members, pending }

    private var pendingCount: Int {
        invitations.filter { $0.isActive }.count
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                tabs
                Group {
                    switch tab {
                    case .members: membersList
                    case .pending: pendingList
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteMembersView()
                .environment(workspaceStore)
                .onDisappear { Task { await loadAll() } }
        }
        .task { await loadAll() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("People")
                    .font(Kin.inter(22, weight: .bold))
                    .foregroundStyle(Kin.textPrimary)
                if let ws = workspaceStore.current {
                    Text("Members of \(ws.name)")
                        .font(Kin.inter(13))
                        .foregroundStyle(Kin.textTertiary)
                }
            }
            Spacer()
            Button { showInviteSheet = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                        .font(.system(size: 12, weight: .medium))
                    Text("Invite")
                        .font(Kin.inter(13, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Kin.accent)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tab switcher

    private var tabs: some View {
        HStack(spacing: 2) {
            tabButton("Members", count: members.count, tab: .members)
            tabButton("Pending invites", count: pendingCount, tab: .pending)
            Spacer()
        }
    }

    private func tabButton(_ label: String, count: Int, tab target: Tab) -> some View {
        Button { tab = target } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(Kin.inter(13, weight: tab == target ? .semibold : .medium))
                    .foregroundStyle(tab == target ? Kin.textPrimary : Kin.textTertiary)
                if count > 0 {
                    Text("\(count)")
                        .font(Kin.inter(11, weight: .semibold))
                        .foregroundStyle(tab == target ? Kin.textPrimary : Kin.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Kin.inputBg)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tab == target ? Kin.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Members list

    @ViewBuilder
    private var membersList: some View {
        if loading && members.isEmpty {
            loadingState
        } else if let err = membersError {
            errorState(err)
        } else if members.isEmpty {
            emptyState(icon: "person.2", title: "No members yet", subtitle: "Invite teammates to collaborate.")
        } else {
            VStack(spacing: 0) {
                ForEach(members) { m in
                    MemberRow(member: m, isYou: m.userId == session.currentUser?.id)
                    if m.id != members.last?.id {
                        Divider().background(Kin.border)
                    }
                }
            }
            .background(Kin.surface)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Kin.border, lineWidth: 1))
        }
    }

    // MARK: - Pending invites list

    @ViewBuilder
    private var pendingList: some View {
        let active = invitations.filter { $0.isActive }
        let inactive = invitations.filter { !$0.isActive }

        if loading && invitations.isEmpty {
            loadingState
        } else if let err = invitesError {
            errorState(err)
        } else if active.isEmpty && inactive.isEmpty {
            emptyState(icon: "envelope", title: "No pending invites", subtitle: "Generate an invite code to bring someone on.")
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if !active.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(active) { inv in
                            PendingInviteRow(inv: inv)
                            if inv.id != active.last?.id {
                                Divider().background(Kin.border)
                            }
                        }
                    }
                    .background(Kin.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Kin.border, lineWidth: 1))
                }

                if !inactive.isEmpty {
                    Text("Expired or used")
                        .font(Kin.inter(11, weight: .semibold))
                        .foregroundStyle(Kin.textTertiary)
                        .tracking(0.5)
                        .padding(.top, 4)

                    VStack(spacing: 0) {
                        ForEach(inactive) { inv in
                            PendingInviteRow(inv: inv)
                            if inv.id != inactive.last?.id {
                                Divider().background(Kin.border)
                            }
                        }
                    }
                    .background(Kin.surface.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Kin.border, lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Shared states

    private var loadingState: some View {
        HStack {
            Spacer()
            ProgressView().controlSize(.small)
            Spacer()
        }
        .padding(.vertical, 40)
    }

    private func errorState(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 20))
                .foregroundStyle(Kin.statusOffline)
            Text(text)
                .font(Kin.inter(12))
                .foregroundStyle(Kin.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Kin.textQuaternary)
            Text(title)
                .font(Kin.inter(14, weight: .semibold))
                .foregroundStyle(Kin.textSecondary)
            Text(subtitle)
                .font(Kin.inter(12))
                .foregroundStyle(Kin.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .background(Kin.surface.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Kin.border, lineWidth: 1))
    }

    // MARK: - Load

    private func loadAll() async {
        guard let ws = workspaceStore.current else { return }
        loading = true
        membersError = nil
        invitesError = nil
        defer { loading = false }
        // Track each side independently so a failure on one doesn't hide the
        // other, and stale errors don't linger across reloads.
        do {
            members = try await workspaceStore.listMembers(workspaceId: ws.id)
        } catch {
            membersError = error.localizedDescription
            print("[PeoplePage] listMembers failed:", error)
        }
        do {
            invitations = try await workspaceStore.fetchInvitations(for: ws.id)
        } catch {
            invitesError = error.localizedDescription
            print("[PeoplePage] fetchInvitations failed:", error)
        }
    }
}

// MARK: - Member row

private struct MemberRow: View {
    let member: WorkspaceMember
    let isYou: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Kin.accent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(member.initials)
                    .font(Kin.inter(12, weight: .bold))
                    .foregroundStyle(Kin.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(Kin.inter(13, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    if isYou {
                        Text("You")
                            .font(Kin.inter(10, weight: .semibold))
                            .foregroundStyle(Kin.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Kin.inputBg)
                            .clipShape(Capsule())
                    }
                }
                Text(member.email)
                    .font(Kin.inter(11))
                    .foregroundStyle(Kin.textTertiary)
            }

            Spacer()

            Text(member.role.capitalized)
                .font(Kin.inter(11, weight: .medium))
                .foregroundStyle(member.isOwner ? Kin.accent : Kin.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((member.isOwner ? Kin.accent : Kin.textTertiary).opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

// MARK: - Pending invite row

private struct PendingInviteRow: View {
    let inv: KinInvitation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "envelope")
                .font(.system(size: 14))
                .foregroundStyle(Kin.textTertiary)
                .frame(width: 36, height: 36)
                .background(Kin.inputBg)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(inv.email ?? "Open invite")
                        .font(Kin.inter(13, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    if inv.isRedeemed {
                        badge("Used", color: Kin.textQuaternary)
                    } else if inv.isExpired {
                        badge("Expired", color: Kin.statusOffline)
                    }
                }
                Text(inv.code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Kin.textTertiary)
            }

            Spacer()

            Text(relativeExpiry)
                .font(Kin.inter(11))
                .foregroundStyle(Kin.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
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

    private var relativeExpiry: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        let prefix = inv.isExpired ? "Expired " : "Expires "
        return prefix + f.localizedString(for: inv.expiresAt, relativeTo: Date())
    }
}
