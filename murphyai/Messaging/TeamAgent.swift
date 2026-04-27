import Foundation

// Server-stored team agent config. Lives in the `agents` table, workspace-scoped.
// Unlike personal AgentConfig (local, has folder/memory access), team agents are
// shared across workspace members and run via first-claim execution.
struct TeamAgent: Identifiable, Decodable, Equatable, Sendable {
    let id: UUID
    let workspaceId: UUID
    let slug: String
    let displayName: String
    let systemPrompt: String
    let model: String
    let avatarTint: String?
    let createdBy: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, slug, model
        case workspaceId   = "workspace_id"
        case displayName   = "display_name"
        case systemPrompt  = "system_prompt"
        case avatarTint    = "avatar_tint"
        case createdBy     = "created_by"
        case createdAt     = "created_at"
    }

    // Ephemeral AgentConfig for use with ClaudeRunner.
    // Team agents get no folder access, no local memory — transcript IS memory.
    func asAgentConfig() -> AgentConfig {
        AgentConfig(
            id: id.uuidString,
            name: displayName,
            role: "",
            icon: "sparkles",
            tint: avatarTint ?? "#7BA4FF",
            systemPrompt: systemPrompt,
            skills: [],
            folderPaths: []
        )
    }
}
