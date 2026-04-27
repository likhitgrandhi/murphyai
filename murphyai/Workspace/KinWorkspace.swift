import Foundation

struct KinWorkspace: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let name: String
    let slug: String
    let ownerId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name, slug
        case ownerId   = "owner_id"
        case createdAt = "created_at"
    }

    var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return "\(words[0].prefix(1))\(words[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
