import Foundation

struct InvitePreview: Decodable {
    let workspaceId: UUID
    let workspaceName: String
    let workspaceSlug: String
    let invitedByName: String
    let memberCount: Int
    let expiresAt: Date
    let emailGated: Bool
    let alreadyMember: Bool

    enum CodingKeys: String, CodingKey {
        case workspaceId   = "workspace_id"
        case workspaceName = "workspace_name"
        case workspaceSlug = "workspace_slug"
        case invitedByName = "invited_by_name"
        case memberCount   = "member_count"
        case expiresAt     = "expires_at"
        case emailGated    = "email_gated"
        case alreadyMember = "already_member"
    }
}

struct KinInvitation: Decodable, Identifiable {
    let id: UUID
    let workspaceId: UUID
    let email: String?
    let code: String
    let invitedBy: UUID
    let role: String
    let expiresAt: Date
    let redeemedBy: UUID?
    let redeemedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, email, code, role
        case workspaceId = "workspace_id"
        case invitedBy   = "invited_by"
        case expiresAt   = "expires_at"
        case redeemedBy  = "redeemed_by"
        case redeemedAt  = "redeemed_at"
    }

    var isRedeemed: Bool { redeemedBy != nil }
    var isExpired: Bool { expiresAt < Date() }
    var isActive: Bool { !isRedeemed && !isExpired }

    var deepLink: String { "kin://join?code=\(code)" }
}
