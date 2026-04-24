import Foundation
import Observation

@Observable
class AgentStore {
    var agents: [AgentConfig] = []

    let baseDir: URL

    init() {
        baseDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kin", isDirectory: true)
        loadAgents()
        loadChannels()
    }

    // MARK: - Load

    func loadAgents() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: baseDir.path),
              let contents = try? fm.contentsOfDirectory(
                at: baseDir, includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles)
        else { seedDefaults(); return }

        var loaded: [AgentConfig] = contents.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            guard let data = try? Data(contentsOf: url.appendingPathComponent("config.json")),
                  var config = try? JSONDecoder().decode(AgentConfig.self, from: data)
            else { return nil }
            // Auto-detect avatar file alongside config.json
            let svgURL = url.appendingPathComponent("avatar.svg")
            let pngURL = url.appendingPathComponent("avatar.png")
            if config.avatarPath == nil {
                if fm.fileExists(atPath: svgURL.path) { config.avatarPath = svgURL.path }
                else if fm.fileExists(atPath: pngURL.path) { config.avatarPath = pngURL.path }
            }
            return config
        }

        if loaded.isEmpty { seedDefaults(); return }

        // Generate tinted avatar for any agent that still has none
        for i in loaded.indices where loaded[i].avatarPath == nil {
            loaded[i].avatarPath = generateAvatar(for: loaded[i])
        }
        agents = loaded
        ensureDefaults()
    }

    /// Adds any default agent whose id is not present on disk. Idempotent.
    /// Runs on every launch so new built-in agents appear for existing users.
    private func ensureDefaults() {
        let existing = Set(agents.map { $0.id })
        for def in AgentConfig.defaultAgents where !existing.contains(def.id) {
            save(def)
        }
    }

    // MARK: - Save

    func save(_ agent: AgentConfig) {
        var agent = agent
        let fm = FileManager.default
        let dir = agentDirectory(for: agent)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let memURL = dir.appendingPathComponent("memory.md")
        if !fm.fileExists(atPath: memURL.path) {
            try? "".write(to: memURL, atomically: true, encoding: .utf8)
        }
        // Generate tinted avatar for new agents
        if agent.avatarPath == nil {
            agent.avatarPath = generateAvatar(for: agent)
        }
        if let data = try? JSONEncoder().encode(agent) {
            try? data.write(to: dir.appendingPathComponent("config.json"), options: .atomic)
        }
        if let idx = agents.firstIndex(where: { $0.id == agent.id }) {
            agents[idx] = agent
        } else {
            agents.append(agent)
        }
    }

    // MARK: - Archive / Delete

    func archive(_ agent: AgentConfig) {
        var updated = agent
        updated.isArchived = true
        save(updated)
    }

    func delete(_ agent: AgentConfig) {
        try? FileManager.default.removeItem(at: agentDirectory(for: agent))
        agents.removeAll { $0.id == agent.id }
    }

    func clearMemory(for agent: AgentConfig) {
        try? "".write(to: memoryURL(for: agent), atomically: true, encoding: .utf8)
    }

    // MARK: - Queries

    var activeAgents: [AgentConfig] {
        agents.filter { !$0.isArchived }
    }

    // MARK: - Paths

    func agentDirectory(for agent: AgentConfig) -> URL {
        baseDir.appendingPathComponent(agent.id, isDirectory: true)
    }

    var avatarsDir: URL {
        let dir = baseDir.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Pixabot avatar refresh

    /// Downloads pixabot avatars for all agents in parallel and persists the paths.
    /// Skips only agents whose PNG already exists on disk with a valid size.
    func refreshPixabotAvatars() async {
        let snapshot = agents
        await withTaskGroup(of: (String, String)?.self) { group in
            for agent in snapshot {
                let dest = agentDirectory(for: agent)
                    .appendingPathComponent("avatar_pixabot.png")
                let agentId = agent.id
                let agentName = agent.name
                let gifDest = agentDirectory(for: agent)
                    .appendingPathComponent("avatar_pixabot.gif")
                group.addTask {
                    guard let path = await PixabotAvatar.downloadAvatar(for: agentName, to: dest)
                    else { return nil }
                    // Download animated GIF alongside; fire-and-forget if it fails
                    _ = await PixabotAvatar.downloadAvatar(for: agentName, to: gifDest, animated: true)
                    return (agentId, path)
                }
            }

            for await result in group {
                guard let (agentId, path) = result,
                      let i = agents.firstIndex(where: { $0.id == agentId })
                else { continue }
                agents[i].avatarPath = path
                let updated = agents[i]
                if let data = try? JSONEncoder().encode(updated) {
                    try? data.write(
                        to: agentDirectory(for: updated).appendingPathComponent("config.json"),
                        options: .atomic
                    )
                }
            }
        }
    }

    func memoryURL(for agent: AgentConfig) -> URL {
        agentDirectory(for: agent).appendingPathComponent("memory.md")
    }

    func memoryContent(for agent: AgentConfig) -> String {
        (try? String(contentsOf: memoryURL(for: agent), encoding: .utf8)) ?? ""
    }

    // MARK: - Private

    private func seedDefaults() {
        AgentConfig.defaultAgents.forEach { save($0) }
    }

    @discardableResult
    private func generateAvatar(for agent: AgentConfig) -> String? {
        guard let url = Bundle.main.url(forResource: "avatar_base", withExtension: "svg"),
              var svg = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        svg = svg.replacingOccurrences(of: "#FFB417", with: agent.tint.uppercased())
        let dest = agentDirectory(for: agent).appendingPathComponent("avatar.svg")
        try? svg.write(to: dest, atomically: true, encoding: .utf8)
        return dest.path
    }

    // MARK: - Channels

    var channels: [Channel] = []

    var activeChannels: [Channel] { channels.filter { !$0.isArchived } }

    func loadChannels() {
        let fm = FileManager.default
        let dir = baseDir.appendingPathComponent("channels", isDirectory: true)
        guard fm.fileExists(atPath: dir.path),
              let contents = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey],
                options: .skipsHiddenFiles)
        else { return }

        channels = contents.compactMap { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            guard let data = try? Data(contentsOf: url.appendingPathComponent("config.json")),
                  let ch = try? JSONDecoder().decode(Channel.self, from: data)
            else { return nil }
            return ch
        }
    }

    func saveChannel(_ channel: Channel) {
        let fm = FileManager.default
        let dir = channelDirectory(for: channel)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(channel) {
            try? data.write(to: dir.appendingPathComponent("config.json"), options: .atomic)
        }
        if let idx = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[idx] = channel
        } else {
            channels.append(channel)
        }
    }

    func deleteChannel(_ channel: Channel) {
        try? FileManager.default.removeItem(at: channelDirectory(for: channel))
        channels.removeAll { $0.id == channel.id }
    }

    func channelDirectory(for channel: Channel) -> URL {
        baseDir.appendingPathComponent("channels/\(channel.id)", isDirectory: true)
    }

}
