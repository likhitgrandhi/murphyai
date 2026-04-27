import SwiftUI

// Pick a workspace member, get-or-create a 1:1 DM, navigate to it.
// Idempotent on the server side via create_dm — re-clicking the same member
// just resolves to the existing channel.
struct NewDMSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SharedChannelStore.self) private var store
    @Environment(SessionStore.self) private var session

    var onOpened: ((ServerChannel) -> Void)? = nil

    @State private var query = ""
    @State private var opening: UUID?    // user id we're currently opening a DM for
    @State private var errorMessage: String?

    private var members: [WorkspaceMember] {
        let me = session.currentUser?.id
        let all = store.membersById.values
            .filter { $0.userId != me }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
        guard !query.isEmpty else { return all }
        let q = query.lowercased()
        return all.filter { $0.name.lowercased().contains(q) || $0.email.lowercased().contains(q) }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().background(Kin.border)
            search
            Divider().background(Kin.border)
            list
        }
        .frame(width: 420, height: 480)
        .background(Kin.bg)
    }

    private var titleBar: some View {
        HStack {
            Text("New direct message")
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

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Kin.textTertiary)
            TextField("Find a teammate", text: $query)
                .textFieldStyle(.plain)
                .font(Kin.inter(12))
                .foregroundStyle(Kin.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Kin.inputBg)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 0) {
                if members.isEmpty {
                    Text(query.isEmpty ? "No teammates in this workspace yet."
                                       : "No matches for \"\(query)\".")
                        .font(Kin.inter(12))
                        .foregroundStyle(Kin.textTertiary)
                        .padding(.vertical, 30)
                }
                ForEach(members) { m in
                    Button { open(m) } label: {
                        HStack(spacing: 10) {
                            ZStack {
                                Circle().fill(Kin.accent.opacity(0.15)).frame(width: 32, height: 32)
                                Text(m.initials)
                                    .font(Kin.inter(11, weight: .bold))
                                    .foregroundStyle(Kin.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.name)
                                    .font(Kin.inter(13, weight: .semibold))
                                    .foregroundStyle(Kin.textPrimary)
                                Text(m.email)
                                    .font(Kin.inter(11))
                                    .foregroundStyle(Kin.textTertiary)
                            }
                            Spacer()
                            if opening == m.userId {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(opening != nil)
                    if m.id != members.last?.id {
                        Divider().background(Kin.border).padding(.leading, 56)
                    }
                }
                if let err = errorMessage {
                    Text(err)
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.statusOffline)
                        .padding(14)
                }
            }
            .padding(.bottom, 14)
        }
    }

    private func open(_ member: WorkspaceMember) {
        guard opening == nil else { return }
        opening = member.userId
        errorMessage = nil
        Task {
            defer { opening = nil }
            do {
                let ch = try await store.openDM(with: member.userId)
                onOpened?(ch)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
