import Foundation
import Observation
import Supabase
import Realtime

// Workspace-scoped roster of team agents. Knows which agents live in each channel.
// Injected into the environment via WorkspaceScope.
@Observable
@MainActor
final class AgentRoster {
    var allAgents: [TeamAgent] = []
    var agentsByChannel: [UUID: [TeamAgent]] = [:]
    var isLoading = false
    var error: String?

    private var workspaceId: UUID?
    private var realtimeChannel: RealtimeChannelV2?
    private var realtimeTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func bind(workspaceId: UUID) async {
        if self.workspaceId == workspaceId { return }
        await teardown()
        self.workspaceId = workspaceId
        await refresh()
        await subscribe()
    }

    func reset() async {
        await teardown()
        workspaceId = nil
        allAgents = []
        agentsByChannel = [:]
        error = nil
    }

    private func teardown() async {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let ch = realtimeChannel {
            await ch.unsubscribe()
            await kinSupabase.realtimeV2.removeChannel(ch)
        }
        realtimeChannel = nil
    }

    private func subscribe() async {
        guard let wsId = workspaceId else { return }
        let ch = kinSupabase.realtimeV2.channel("kin-roster-\(wsId.uuidString)")
        realtimeChannel = ch

        // agents: workspace-filtered. Any change to the roster — new agent,
        // archive, rename — re-pulls the list.
        let agentsAny = ch.postgresChange(
            AnyAction.self, schema: "public", table: "agents",
            filter: "workspace_id=eq.\(wsId.uuidString)"
        )
        // channel_agents: no workspace filter on the table, but RLS limits
        // events to channels we're a member of. On change, refresh that channel.
        let channelAgentsAny = ch.postgresChange(
            AnyAction.self, schema: "public", table: "channel_agents"
        )

        // Drain the @MainActor task queue so the binding-registration Tasks
        // (scheduled inside `postgresChange()`) complete before subscribe builds
        // the JOIN payload. Without this, the JOIN goes out with empty bindings
        // and the server never delivers events even though the channel reaches
        // `subscribed` state. Same fix applied in SharedChannelStore.subscribe().
        await Task.yield()

        // Subscribe in a sibling Task; the consumer task group below runs
        // independently so events delivered after auto-reconnect (post initial
        // timeout) still reach the for-await loops.
        Task {
            do {
                try await ch.subscribeWithError()
            } catch {
                print("[AgentRoster] realtime subscribe initial failed:", error, "— listening for auto-reconnect")
            }
        }
        realtimeTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await _ in agentsAny {
                        if Task.isCancelled { break }
                        await self?.refresh()
                    }
                }
                group.addTask { [weak self] in
                    for await action in channelAgentsAny {
                        if Task.isCancelled { break }
                        if let channelId = Self.affectedChannelId(from: action) {
                            await self?.refreshChannelAgents(for: channelId)
                        }
                    }
                }
            }
        }
    }

    nonisolated private static func affectedChannelId(from action: AnyAction) -> UUID? {
        // Pull channel_id from the record (insert/update) or oldRecord (delete).
        struct Row: Decodable {
            let channelId: UUID
            enum CodingKeys: String, CodingKey { case channelId = "channel_id" }
        }
        switch action {
        case .insert(let a): return (try? a.decodeRecord(as: Row.self, decoder: JSONDecoder()))?.channelId
        case .update(let a): return (try? a.decodeRecord(as: Row.self, decoder: JSONDecoder()))?.channelId
        case .delete(let a): return (try? a.decodeOldRecord(as: Row.self, decoder: JSONDecoder()))?.channelId
        default: return nil
        }
    }

    // MARK: - Queries

    func agents(in channelId: UUID) -> [TeamAgent] {
        agentsByChannel[channelId] ?? []
    }

    func agent(slug: String, in channelId: UUID) -> TeamAgent? {
        agents(in: channelId).first { $0.slug.lowercased() == slug.lowercased() }
    }

    // MARK: - Fetch

    func refresh() async {
        guard let wsId = workspaceId else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let agents: [TeamAgent] = try await kinSupabase
                .rpc("list_workspace_agents", params: WorkspaceAgentParams(workspaceId: wsId))
                .execute()
                .value
            allAgents = agents
        } catch {
            self.error = error.localizedDescription
            print("[AgentRoster] refresh failed:", error)
        }
    }

    func refreshChannelAgents(for channelId: UUID) async {
        do {
            let agents: [TeamAgent] = try await kinSupabase
                .rpc("list_channel_agents", params: ChannelAgentParams(channelId: channelId))
                .execute()
                .value
            agentsByChannel[channelId] = agents
        } catch {
            print("[AgentRoster] refreshChannelAgents failed:", error)
        }
    }

    // MARK: - Mutations

    @discardableResult
    func createAgent(
        name: String, slug: String, systemPrompt: String,
        model: String, avatarTint: String? = nil
    ) async throws -> TeamAgent {
        guard let wsId = workspaceId else { throw AgentRosterError.notReady }
        let agent: TeamAgent = try await kinSupabase
            .rpc("create_team_agent", params: CreateTeamAgentParams(
                workspaceId: wsId, slug: slug, displayName: name,
                systemPrompt: systemPrompt, model: model, avatarTint: avatarTint
            ))
            .execute()
            .value
        if !allAgents.contains(where: { $0.id == agent.id }) {
            allAgents.append(agent)
        }
        return agent
    }

    // Promote a personal (local) agent to a team agent and add it to a channel.
    // If a team agent with the same slug already exists in this workspace,
    // reuse it instead of trying to insert a duplicate (which would violate
    // the unique(workspace_id, slug) constraint).
    @discardableResult
    func shareAndAdd(personal: AgentConfig, channelId: UUID) async throws -> TeamAgent {
        let slug = personal.id.lowercased()
        let team: TeamAgent
        if let existing = allAgents.first(where: { $0.slug.lowercased() == slug }) {
            team = existing
        } else {
            team = try await createAgent(
                name: personal.name,
                slug: slug,
                systemPrompt: personal.systemPrompt,
                model: ClaudeRunner.selectedModel,
                avatarTint: personal.tint
            )
        }
        try await addToChannel(agentId: team.id, channelId: channelId)
        return team
    }

    func addToChannel(agentId: UUID, channelId: UUID) async throws {
        try await kinSupabase
            .from("channel_agents")
            .insert(ChannelAgentRow(channelId: channelId, agentId: agentId))
            .execute()
        await refreshChannelAgents(for: channelId)
    }

    func removeFromChannel(agentId: UUID, channelId: UUID) async throws {
        try await kinSupabase
            .from("channel_agents")
            .delete()
            .eq("channel_id", value: channelId)
            .eq("agent_id", value: agentId)
            .execute()
        agentsByChannel[channelId]?.removeAll { $0.id == agentId }
    }
}

// MARK: - Errors

enum AgentRosterError: LocalizedError {
    case notReady
    var errorDescription: String? {
        "Workspace not ready."
    }
}

// MARK: - RPC / row param types

private struct WorkspaceAgentParams: Encodable {
    let workspaceId: UUID
    enum CodingKeys: String, CodingKey { case workspaceId = "p_workspace_id" }
}

private struct ChannelAgentParams: Encodable {
    let channelId: UUID
    enum CodingKeys: String, CodingKey { case channelId = "p_channel_id" }
}

private struct CreateTeamAgentParams: Encodable {
    let workspaceId: UUID
    let slug: String
    let displayName: String
    let systemPrompt: String
    let model: String
    let avatarTint: String?
    enum CodingKeys: String, CodingKey {
        case workspaceId  = "p_workspace_id"
        case slug         = "p_slug"
        case displayName  = "p_display_name"
        case systemPrompt = "p_system_prompt"
        case model        = "p_model"
        case avatarTint   = "p_avatar_tint"
    }
}

private struct ChannelAgentRow: Encodable {
    let channelId: UUID
    let agentId: UUID
    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case agentId   = "agent_id"
    }
}
