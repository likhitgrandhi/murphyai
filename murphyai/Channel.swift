import Foundation

// MARK: - Channel model

struct Channel: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var topic: String
    var memberAgentIds: [String]
    var folderPaths: [String]
    var triggerRules: [TriggerRule]
    var chainingEnabled: Bool
    var isArchived: Bool

    init(
        id: String, name: String, topic: String,
        memberAgentIds: [String], folderPaths: [String] = [],
        triggerRules: [TriggerRule] = [], chainingEnabled: Bool = true,
        isArchived: Bool = false
    ) {
        self.id = id; self.name = name; self.topic = topic
        self.memberAgentIds = memberAgentIds; self.folderPaths = folderPaths
        self.triggerRules = triggerRules; self.chainingEnabled = chainingEnabled
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id              = try c.decode(String.self, forKey: .id)
        name            = try c.decode(String.self, forKey: .name)
        topic           = try c.decodeIfPresent(String.self, forKey: .topic) ?? ""
        memberAgentIds  = try c.decodeIfPresent([String].self, forKey: .memberAgentIds) ?? []
        folderPaths     = try c.decodeIfPresent([String].self, forKey: .folderPaths) ?? []
        triggerRules    = try c.decodeIfPresent([TriggerRule].self, forKey: .triggerRules) ?? []
        chainingEnabled = try c.decodeIfPresent(Bool.self, forKey: .chainingEnabled) ?? true
        isArchived      = try c.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }
}

// MARK: - Trigger rule

struct TriggerRule: Codable, Identifiable, Equatable {
    var id: String
    var afterAgentId: String
    var invokeAgentId: String

    init(afterAgentId: String, invokeAgentId: String) {
        self.id = UUID().uuidString
        self.afterAgentId = afterAgentId
        self.invokeAgentId = invokeAgentId
    }
}

// MARK: - Channel message (in-memory)

struct ChannelMessage: Identifiable, Codable {
    let id: UUID
    let date: Date
    var sender: Sender
    var content: String
    var thinking: String
    var toolCards: [ToolCard]
    var isStreaming: Bool

    init(sender: Sender, content: String = "", thinking: String = "",
         toolCards: [ToolCard] = [], isStreaming: Bool = false) {
        self.id = UUID()
        self.date = Date()
        self.sender = sender
        self.content = content
        self.thinking = thinking
        self.toolCards = toolCards
        self.isStreaming = isStreaming
    }

    enum Sender: Equatable, Codable {
        case user
        case agent(id: String)
    }
}
