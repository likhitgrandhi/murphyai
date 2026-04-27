import SwiftUI

// MARK: - Shared avatar (used in ChatView, ChannelView, NewAgentSheet)

struct AgentAvatarCircle: View {
    let name: String
    let tint: String
    let size: CGFloat
    var avatarPath: String? = nil
    var status: AgentStatus? = nil   // nil = no dot
    var animated: Bool = false       // show GIF while agent is thinking

    private var tintColor: Color { Color(hex: tint) ?? Kin.accent }
    private var initial: String { String(name.first ?? "?").uppercased() }

    // Derives the GIF path from the PNG path (same directory, different extension)
    private var gifPath: String? {
        guard let p = avatarPath else { return nil }
        let candidate = p.replacingOccurrences(of: "avatar_pixabot.png", with: "avatar_pixabot.gif")
        return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if animated, let gif = gifPath {
                    AnimatedGifView(path: gif)
                        .frame(width: size, height: size)
                        .clipped()
                } else if let path = avatarPath,
                   let nsImage = NSImage(contentsOfFile: path) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                } else {
                    ZStack {
                        Circle().fill(tintColor.opacity(0.18))
                        Text(initial)
                            .font(Kin.inter(size * 0.43, weight: .semibold))
                            .foregroundStyle(tintColor)
                    }
                    .overlay(Circle().stroke(tintColor.opacity(0.35), lineWidth: 1.5))
                    .frame(width: size, height: size)
                }
            }

            if let status {
                statusDot(status)
                    .offset(x: 2, y: 2)
            }
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder
    private func statusDot(_ status: AgentStatus) -> some View {
        switch status {
        case .online:
            Circle()
                .fill(Kin.statusOnline)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Kin.sidebarBg, lineWidth: 2))
        case .snooze:
            ZStack {
                Circle().fill(Kin.statusSnooze)
                Image(systemName: "moon.fill")
                    .font(.system(size: 5, weight: .bold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(-30))
            }
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Kin.sidebarBg, lineWidth: 2))
        case .offline:
            Circle()
                .fill(Kin.statusOffline)
                .frame(width: 10, height: 10)
                .overlay(Circle().stroke(Kin.sidebarBg, lineWidth: 2))
        }
    }
}

// MARK: - Top bar (40pt, spans full window width above server strip + content)

struct TopBarView: View {
    enum Icon {
        case hash, at, messages

        var systemName: String {
            switch self {
            case .hash: return "number"
            case .at: return "at"
            case .messages: return "bubble.left.and.bubble.right.fill"
            }
        }
    }

    let title: String
    let icon: Icon

    var body: some View {
        ZStack {
            HStack(spacing: 6) {
                Image(systemName: icon.systemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Kin.textSecondary)
                Text(title)
                    .font(Kin.inter(14, weight: .semibold))
                    .foregroundStyle(Kin.textPrimary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(Kin.serverBg)
    }
}

// MARK: - Server strip (72pt, sits OUTSIDE the bordered container)

struct ServerStripView: View {
    @Binding var showNewChannel: Bool

    var body: some View {
        VStack(spacing: 0) {
            Button {} label: {
                ZStack {
                    Circle()
                        .fill(Kin.avatarBg)
                        .frame(width: 48, height: 48)
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Kin.accent)
                }
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.9))
            .frame(width: 72, height: 48)

            Rectangle()
                .fill(Kin.border)
                .frame(width: 32, height: 1)
                .padding(.vertical, 8)

            Button { showNewChannel = true } label: {
                ZStack {
                    Circle()
                        .fill(Kin.avatarBg)
                        .frame(width: 48, height: 48)
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Kin.statusOnline)
                }
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.9))
            .frame(width: 72, height: 48)

            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .frame(width: 72)
        .frame(maxHeight: .infinity)
        .background(Kin.serverBg)
    }
}

// MARK: - Sidebar (channel sidebar only — 272pt, inside the bordered container)

struct SidebarView: View {
    @Environment(AgentStore.self) var store
    @Environment(SharedChannelStore.self) var sharedChannels
    @Environment(AgentRoster.self) var agentRoster
    @Environment(SessionStore.self) var session
    @Binding var selectedAgentId: String?
    @Binding var selectedChannelId: String?
    @Binding var selectedSharedChannelId: UUID?
    @Binding var showNewAgent: Bool
    @Binding var showNewChannel: Bool
    @Binding var showNewDM: Bool
    @Binding var showGlobalSettings: Bool
    @Binding var showInviteMembers: Bool
    var runners: [String: ClaudeRunner] = [:]

    private var sharedDMs: [ServerChannel] {
        sharedChannels.channels.filter { $0.isDM }
    }
    private var sharedRoomChannels: [ServerChannel] {
        sharedChannels.channels.filter { !$0.isDM }
    }

    var body: some View {
        channelSidebar
    }

    // MARK: - Sections (merged: Channels = shared + personal; DMs = humans + personal agents)

    private var channelsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(title: "CHANNELS", onAdd: { showNewChannel = true })
            VStack(spacing: 2) {
                ForEach(sharedRoomChannels) { ch in
                    SidebarSharedChannelRow(
                        channel: ch,
                        isSelected: selectedSharedChannelId == ch.id,
                        unreadCount: sharedChannels.unreadCount(for: ch.id)
                    )
                    .onTapGesture {
                        selectedSharedChannelId = ch.id
                        selectedChannelId = nil
                        selectedAgentId = nil
                    }
                }
                ForEach(store.activeChannels) { channel in
                    SidebarChannelRow(
                        channel: channel,
                        isSelected: selectedChannelId == channel.id
                    )
                    .onTapGesture {
                        selectedChannelId = channel.id
                        selectedAgentId = nil
                        selectedSharedChannelId = nil
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var directMessagesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarSectionHeader(title: "DIRECT MESSAGES") {
                Menu {
                    Button("Message a teammate") { showNewDM = true }
                    Button("New personal agent") { showNewAgent = true }
                } label: {
                    Text("+")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Kin.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            VStack(spacing: 2) {
                ForEach(sharedDMs) { ch in
                    SidebarSharedChannelRow(
                        channel: ch,
                        isSelected: selectedSharedChannelId == ch.id,
                        unreadCount: sharedChannels.unreadCount(for: ch.id)
                    )
                    .onTapGesture {
                        selectedSharedChannelId = ch.id
                        selectedChannelId = nil
                        selectedAgentId = nil
                    }
                }
                ForEach(store.activeAgents) { agent in
                    SidebarAgentRow(
                        agent: agent,
                        isSelected: selectedAgentId == agent.id,
                        runner: runners[agent.id]
                    )
                    .onTapGesture {
                        selectedAgentId = agent.id
                        selectedChannelId = nil
                        selectedSharedChannelId = nil
                    }
                }
            }
            .padding(.horizontal, 8)
        }
    }

    private var teamAgentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // No "+" here — team agents are created by sharing a personal agent
            // into a channel, not as a separate top-level action.
            SidebarSectionHeader(title: "TEAM AGENTS")
            if agentRoster.allAgents.isEmpty {
                Text("Add a personal agent to a channel to share it with the team.")
                    .font(Kin.inter(11))
                    .foregroundStyle(Kin.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 2) {
                    ForEach(agentRoster.allAgents) { agent in
                        SidebarTeamAgentRow(agent: agent)
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Channel sidebar

    private var channelSidebar: some View {
        VStack(spacing: 0) {
            sidebarSearchBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    channelsSection
                    Rectangle().fill(Kin.border).frame(height: 1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)

                    directMessagesSection
                    Rectangle().fill(Kin.border).frame(height: 1)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)

                    teamAgentsSection
                }
                .padding(.bottom, 8)
            }

            profileBar
        }
        .frame(width: 272)
        .frame(maxHeight: .infinity)
        .background(Kin.sidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Kin.border)
                .frame(width: 1)
        }
    }

    // MARK: - Search bar

    private var sidebarSearchBar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Find or start a conversation")
                    .font(Kin.inter(13, weight: .medium))
                    .foregroundStyle(Kin.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(Kin.searchBarBg, in: RoundedRectangle(cornerRadius: 4))
            .padding(.horizontal, 8)
        }
        .frame(height: 48)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Kin.border).frame(height: 1)
        }
    }

    // MARK: - Profile bar

    private var profileBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Kin.border).frame(height: 1)

            HStack(spacing: 0) {
                HStack(spacing: 7) {
                    ZStack {
                        Circle().fill(Kin.avatarBg)
                        Text("Y")
                            .font(Kin.inter(14, weight: .semibold))
                            .foregroundStyle(Kin.textTertiary)
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("You")
                            .font(Kin.inter(14, weight: .semibold))
                            .foregroundStyle(Kin.textPrimary)
                        Text("#0001")
                            .font(Kin.inter(12, weight: .medium))
                            .foregroundStyle(Kin.textSecondary)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                }
                .padding(.leading, 9)
                .padding(.vertical, 4)

                Spacer()

                HStack(spacing: 10) {
                    Button { showInviteMembers = true } label: {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(Kin.textTertiary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PressScaleButtonStyle(scale: 0.88))
                    .help("Invite members")

                    Button { showGlobalSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(Kin.textTertiary)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(PressScaleButtonStyle(scale: 0.88))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 12)
            }
            .frame(height: 56)
            .background(Kin.profileBar, in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Kin.sidebarBg)
    }
}

// MARK: - Section header

private struct SidebarSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    init(title: String, onAdd: @escaping () -> Void) where Trailing == AnyView {
        self.title = title
        self.trailing = {
            AnyView(
                Button { onAdd() } label: {
                    Text("+")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(Kin.textSecondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(PressScaleButtonStyle(scale: 0.88))
            )
        }
    }

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    init(title: String) where Trailing == EmptyView {
        self.title = title
        self.trailing = { EmptyView() }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(Kin.inter(11, weight: .semibold))
                .foregroundStyle(Kin.textSecondary)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            trailing()
        }
        .padding(.horizontal, 8)
        .padding(.top, 20)
        .padding(.bottom, 4)
    }
}

// MARK: - Channel row

private struct SidebarChannelRow: View {
    let channel: Channel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Lock icon — personal/private channel, only visible to you.
            Image(systemName: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isSelected ? Kin.textPrimary : Kin.textSecondary)
                .frame(width: 18)
            Text(channel.name)
                .font(Kin.inter(16, weight: .medium))
                .foregroundStyle(isSelected ? Kin.textPrimary : Kin.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 4).fill(Kin.sidebarSelected)
                : RoundedRectangle(cornerRadius: 4).fill(Color.clear)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: isSelected)
    }
}

// MARK: - Agent (DM) row


private struct SidebarAgentRow: View {
    let agent: AgentConfig
    let isSelected: Bool
    var runner: ClaudeRunner? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            rowContent(at: ctx.date)
        }
    }

    @ViewBuilder
    private func rowContent(at now: Date) -> some View {
        let status = runner?.presenceStatus(at: now) ?? .offline
        HStack(spacing: 10) {
            AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 32, avatarPath: agent.avatarPath, status: status)
            Text(agent.name)
                .font(Kin.inter(16, weight: .medium))
                .foregroundStyle(isSelected ? Kin.textPrimary : Kin.textSecondary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 44)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 8).fill(Kin.sidebarSelected)
                : RoundedRectangle(cornerRadius: 8).fill(Color.clear)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: isSelected)
    }
}

// MARK: - Server-backed channel row (humans only at M6)

// Read-only roster entry — tapping does nothing; agents are invoked via @mention.
struct SidebarTeamAgentRow: View {
    let agent: TeamAgent

    private var tintColor: Color {
        Color(hex: agent.avatarTint ?? "") ?? Kin.accent
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tintColor.opacity(0.18))
                    .frame(width: 20, height: 20)
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tintColor)
            }
            Text("@\(agent.slug)")
                .font(Kin.inter(14, weight: .medium))
                .foregroundStyle(Kin.textQuaternary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .contentShape(Rectangle())
    }
}

struct SidebarSharedChannelRow: View {
    let channel: ServerChannel
    let isSelected: Bool
    var unreadCount: Int = 0

    private var hasUnread: Bool { unreadCount > 0 }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: channel.isDM ? "at" : "number")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected || hasUnread ? Kin.textPrimary : Kin.textSecondary)
                .frame(width: 18)
            Text(channel.displayName)
                .font(Kin.inter(15, weight: hasUnread ? .semibold : .medium))
                .foregroundStyle(isSelected || hasUnread ? Kin.textPrimary : Kin.textSecondary)
                .lineLimit(1)
            Spacer()
            if hasUnread {
                Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                    .font(Kin.inter(10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.red)
                    .clipShape(Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(
            isSelected
                ? RoundedRectangle(cornerRadius: 4).fill(Kin.sidebarSelected)
                : RoundedRectangle(cornerRadius: 4).fill(Color.clear)
        )
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.1), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: unreadCount)
    }
}
