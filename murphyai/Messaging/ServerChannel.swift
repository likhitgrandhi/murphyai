import Foundation

// Server-backed channel — distinct from the local Channel struct used by the
// pre-server multi-agent flows. Lives in the `channels` table.
struct ServerChannel: Decodable, Identifiable, Equatable, Hashable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let name: String?
    let topic: String?
    let isDM: Bool
    let createdBy: UUID
    let createdAt: Date
    let archivedAt: Date?

    // Populated only by list_my_channels for DMs.
    let dmOtherUserId: UUID?
    let dmOtherDisplayName: String?
    let dmOtherEmail: String?

    enum CodingKeys: String, CodingKey {
        case id, name, topic
        case workspaceId         = "workspace_id"
        case isDM                = "is_dm"
        case createdBy           = "created_by"
        case createdAt           = "created_at"
        case archivedAt          = "archived_at"
        case dmOtherUserId       = "dm_other_user_id"
        case dmOtherDisplayName  = "dm_other_display_name"
        case dmOtherEmail        = "dm_other_email"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(UUID.self, forKey: .id)
        workspaceId = try c.decode(UUID.self, forKey: .workspaceId)
        name        = try c.decodeIfPresent(String.self, forKey: .name)
        topic       = try c.decodeIfPresent(String.self, forKey: .topic)
        isDM        = try c.decode(Bool.self, forKey: .isDM)
        createdBy   = try c.decode(UUID.self, forKey: .createdBy)
        createdAt   = try c.decode(Date.self, forKey: .createdAt)
        archivedAt  = try c.decodeIfPresent(Date.self, forKey: .archivedAt)
        dmOtherUserId      = try c.decodeIfPresent(UUID.self,   forKey: .dmOtherUserId)
        dmOtherDisplayName = try c.decodeIfPresent(String.self, forKey: .dmOtherDisplayName)
        dmOtherEmail       = try c.decodeIfPresent(String.self, forKey: .dmOtherEmail)
    }

    // Display name resolution: DM channels use the other party's name; non-DMs
    // use the channel's own name. Falls back to email for DMs missing a profile.
    var displayName: String {
        if isDM {
            return dmOtherDisplayName ?? dmOtherEmail ?? "Direct message"
        }
        return name ?? "channel"
    }
}
