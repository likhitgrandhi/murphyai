import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class WorkspaceStore {
    var workspaces: [KinWorkspace] = []
    var current: KinWorkspace?
    var isLoading = false
    var error: String?
    // Observable set so murphyaiApp.body re-renders when onboarding completes,
    // even when `current` hasn't changed (workspace was already selected).
    var onboardedWorkspaceIds: Set<UUID> = []

    // Keyed by the signed-in user so one device shared by two accounts never
    // reads the other account's onboarding completion or last-workspace choice.
    private var boundUserId: UUID?
    private var onboardedKey: String { "kinOnboardedIds_\(boundUserId?.uuidString ?? "none")" }
    private var lastWorkspaceKey: String { "kinLastWorkspaceId_\(boundUserId?.uuidString ?? "none")" }

    // MARK: - Bootstrap

    func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let fetched: [KinWorkspace] = try await kinSupabase
                .from("workspaces")
                .select()
                .execute()
                .value
            workspaces = fetched
            restoreCurrent(from: fetched)
        } catch {
            self.error = error.localizedDescription
            print("[WorkspaceStore] refresh failed:", error)
        }
    }

    init() {}

    // Call when the session becomes signedIn so per-user state (onboarding
    // completion, last-selected workspace) is loaded from the user's own
    // UserDefaults bucket.
    func bind(userId: UUID) {
        guard boundUserId != userId else { return }
        boundUserId = userId
        let raw = UserDefaults.standard.stringArray(forKey: onboardedKey) ?? []
        onboardedWorkspaceIds = Set(raw.compactMap { UUID(uuidString: $0) })
        migrateLegacyOnboardingKey()
    }

    func reset() {
        workspaces = []
        current = nil
        error = nil
        onboardedWorkspaceIds = []
        boundUserId = nil
    }

    // MARK: - Create

    func create(name: String) async throws -> KinWorkspace {
        let slug = name
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines).joined(separator: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
        do {
            let ws: KinWorkspace = try await kinSupabase
                .rpc("create_workspace", params: CreateWorkspaceParams(
                    workspaceName: name,
                    workspaceSlug: slug.isEmpty ? "workspace" : slug
                ))
                .execute()
                .value
            workspaces.append(ws)
            select(ws)
            return ws
        } catch {
            // The RPC raises 'workspace_slug_exists' when another workspace
            // already owns the derived slug. Map to a friendly, user-facing
            // error instead of surfacing Postgres's exception text.
            if "\(error)".contains("workspace_slug_exists") {
                throw WorkspaceError.nameTaken
            }
            throw error
        }
    }

    // MARK: - Join by invite code

    func joinByCode(_ code: String) async throws -> KinWorkspace {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let raw: Data = try await kinSupabase
            .rpc("redeem_invitation", params: RedeemParams(inviteCode: code.trimmingCharacters(in: .whitespaces)))
            .execute()
            .data
        let result = try decoder.decode(RedeemResult.self, from: raw)
        // The RPC now returns the full workspace row inline — avoids the
        // follow-up SELECT that could race the membership-insert's commit
        // visibility and return zero rows despite a successful join.
        let ws = result.workspace
        if !workspaces.contains(where: { $0.id == ws.id }) {
            workspaces.append(ws)
        }
        select(ws)
        return ws
    }

    // MARK: - Selection

    func select(_ workspace: KinWorkspace) {
        current = workspace
        UserDefaults.standard.set(workspace.id.uuidString, forKey: lastWorkspaceKey)
    }

    // MARK: - Invitations

    func previewInvite(code: String) async throws -> InvitePreview {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let raw: Data = try await kinSupabase
            .rpc("preview_invitation", params: PreviewInviteParams(code: code.trimmingCharacters(in: .whitespaces)))
            .execute()
            .data
        return try decoder.decode(InvitePreview.self, from: raw)
    }

    func createInvitation(workspaceId: UUID, email: String?, role: String = "member") async throws -> KinInvitation {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let inv: KinInvitation = try await kinSupabase
            .rpc("create_invitation", params: CreateInviteParams(
                workspaceId: workspaceId,
                email: email?.lowercased().trimmingCharacters(in: .whitespaces).nilIfEmpty,
                role: role
            ))
            .execute()
            .value
        return inv
    }

    func fetchInvitations(for workspaceId: UUID) async throws -> [KinInvitation] {
        let invitations: [KinInvitation] = try await kinSupabase
            .from("invitations")
            .select()
            .eq("workspace_id", value: workspaceId)
            .order("expires_at", ascending: false)
            .execute()
            .value
        return invitations
    }

    func listMembers(workspaceId: UUID) async throws -> [WorkspaceMember] {
        let members: [WorkspaceMember] = try await kinSupabase
            .rpc("list_workspace_members", params: ListMembersParams(workspaceId: workspaceId))
            .execute()
            .value
        return members
    }

    // MARK: - Onboarding gate (per workspace)

    func hasCompletedOnboarding(for workspaceId: UUID) -> Bool {
        onboardedWorkspaceIds.contains(workspaceId)
    }

    func markOnboardingComplete(for workspaceId: UUID) {
        onboardedWorkspaceIds.insert(workspaceId)
        UserDefaults.standard.set(
            onboardedWorkspaceIds.map(\.uuidString),
            forKey: onboardedKey
        )
    }

    // MARK: - Private

    // Migrate the single-user v1 key `kinOnboardedIds` (device-wide) into the
    // current user's scoped bucket. Only runs once per user — if the scoped
    // key already has entries, the legacy key is ignored and left untouched
    // (it may still belong to a different user on this device).
    private func migrateLegacyOnboardingKey() {
        guard onboardedWorkspaceIds.isEmpty,
              let legacy = UserDefaults.standard.stringArray(forKey: "kinOnboardedIds"),
              !legacy.isEmpty else { return }
        onboardedWorkspaceIds = Set(legacy.compactMap { UUID(uuidString: $0) })
        UserDefaults.standard.set(legacy, forKey: onboardedKey)
        UserDefaults.standard.removeObject(forKey: "kinOnboardedIds")
    }

    private func restoreCurrent(from fetched: [KinWorkspace]) {
        let lastId = UserDefaults.standard.string(forKey: lastWorkspaceKey)
        if let last = fetched.first(where: { $0.id.uuidString == lastId }) {
            current = last
        } else {
            current = fetched.first
        }
        if let c = current {
            UserDefaults.standard.set(c.id.uuidString, forKey: lastWorkspaceKey)
        }
    }
}

// MARK: - RPC param / result types

private struct CreateWorkspaceParams: Encodable {
    let workspaceName: String
    let workspaceSlug: String
    enum CodingKeys: String, CodingKey {
        case workspaceName = "workspace_name"
        case workspaceSlug = "workspace_slug"
    }
}

private struct RedeemParams: Encodable {
    let inviteCode: String
    enum CodingKeys: String, CodingKey {
        case inviteCode = "invite_code"
    }
}

struct RedeemResult: Decodable {
    let workspaceId: String
    let alreadyMember: Bool
    let workspace: KinWorkspace
    enum CodingKeys: String, CodingKey {
        case workspaceId   = "workspace_id"
        case alreadyMember = "already_member"
        case workspace
    }
}

enum WorkspaceError: LocalizedError {
    case invalidResponse
    case nameTaken
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Unexpected server response."
        case .nameTaken:       return "That workspace name is already taken. Try another."
        }
    }
}

private struct PreviewInviteParams: Encodable {
    let code: String
    enum CodingKeys: String, CodingKey { case code = "p_code" }
}

private struct ListMembersParams: Encodable {
    let workspaceId: UUID
    enum CodingKeys: String, CodingKey { case workspaceId = "p_workspace_id" }
}

private struct CreateInviteParams: Encodable {
    let workspaceId: UUID
    let email: String?
    let role: String
    enum CodingKeys: String, CodingKey {
        case workspaceId = "p_workspace_id"
        case email       = "p_email"
        case role        = "p_role"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
