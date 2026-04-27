import Foundation

// Wire-format message row from the `messages` table. Decoded from both
// initial fetches (REST) and realtime INSERT events (Postgres Changes payload).
struct ServerMessage: Decodable, Identifiable, Equatable, Hashable, Sendable {
    enum SenderKind: String, Decodable, Sendable {
        case user, agent, system
    }

    struct ToolCard: Codable, Equatable, Hashable, Sendable {
        let name: String
        let summary: String
        let ok: Bool
    }

    let id: UUID
    let channelId: UUID
    let seq: Int64
    let senderKind: SenderKind
    let senderUserId: UUID?
    let agentId: UUID?
    let agentSlug: String?
    let agentDisplayName: String?
    let runByUserId: UUID?
    let content: String?
    let thinking: String?
    let toolCards: [ToolCard]?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, seq, content, thinking
        case channelId         = "channel_id"
        case senderKind        = "sender_kind"
        case senderUserId      = "sender_user_id"
        case agentId           = "agent_id"
        case agentSlug         = "agent_slug"
        case agentDisplayName  = "agent_display_name"
        case runByUserId       = "run_by_user_id"
        case toolCards         = "tool_cards"
        case createdAt         = "created_at"
    }
}

// Sort tuple for stable per-channel ordering. Use seq as the primary key —
// it's monotonic per channel, survives clock skew, and is what we use for
// keyset-paginated reconnect resync.
extension ServerMessage: Comparable {
    static func < (lhs: ServerMessage, rhs: ServerMessage) -> Bool {
        lhs.seq < rhs.seq
    }
}
