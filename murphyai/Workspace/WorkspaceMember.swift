import Foundation

struct WorkspaceMember: Decodable, Identifiable {
    let userId: UUID
    let email: String
    let displayName: String?
    let avatarURL: String?
    let role: String
    let joinedAt: Date

    var id: UUID { userId }

    var name: String { displayName ?? email }

    var initials: String {
        let name = displayName ?? email
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    var isOwner: Bool { role == "owner" }

    enum CodingKeys: String, CodingKey {
        case userId      = "user_id"
        case email
        case displayName = "display_name"
        case avatarURL   = "avatar_url"
        case role
        case joinedAt    = "joined_at"
    }
}
