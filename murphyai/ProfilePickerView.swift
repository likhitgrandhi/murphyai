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
                    .foregroundStyle(.white)
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
    @Binding var selectedAgentId: String?
    @Binding var selectedChannelId: String?
    @Binding var showNewAgent: Bool
    @Binding var showNewChannel: Bool
    @Binding var showGlobalSettings: Bool
    var runners: [String: ClaudeRunner] = [:]

    var body: some View {
        channelSidebar
    }

    // MARK: - Channel sidebar

    private var channelSidebar: some View {
        VStack(spacing: 0) {
            sidebarSearchBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        SidebarSectionHeader(title: "CHANNELS", onAdd: { showNewChannel = true })
                        if !store.activeChannels.isEmpty {
                            VStack(spacing: 2) {
                                ForEach(store.activeChannels) { channel in
                                    SidebarChannelRow(
                                        channel: channel,
                                        isSelected: selectedChannelId == channel.id
                                    )
                                    .onTapGesture {
                                        selectedChannelId = channel.id
                                        selectedAgentId = nil
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                        }

                        Rectangle().fill(Kin.border).frame(height: 1)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SidebarSectionHeader(title: "DIRECT MESSAGES", onAdd: { showNewAgent = true })
                        VStack(spacing: 2) {
                            ForEach(store.activeAgents) { agent in
                                SidebarAgentRow(
                                    agent: agent,
                                    isSelected: selectedAgentId == agent.id,
                                    runner: runners[agent.id]
                                )
                                .onTapGesture {
                                    selectedAgentId = agent.id
                                    selectedChannelId = nil
                                }
                            }
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.bottom, 8)
            }

            profileBar
        }
        .frame(width: 272)
        .frame(maxHeight: .infinity)
        .background(Kin.sidebarBg)
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
                            .foregroundStyle(.white)
                        Text("#0001")
                            .font(Kin.inter(12, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.45))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                }
                .padding(.leading, 9)
                .padding(.vertical, 4)

                Spacer()

                HStack(spacing: 10) {
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

private struct SidebarSectionHeader: View {
    let title: String
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(Kin.inter(11, weight: .semibold))
                .foregroundStyle(Kin.textSecondary)
                .tracking(0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)

            Button { onAdd() } label: {
                Text("+")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Kin.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.88))
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
            Text("#")
                .font(Kin.inter(18, weight: .semibold))
                .foregroundStyle(isSelected ? .white : Kin.textQuaternary)
                .frame(width: 18)
            Text(channel.name)
                .font(Kin.inter(16, weight: .medium))
                .foregroundStyle(isSelected ? .white : Kin.textQuaternary)
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
                .foregroundStyle(isSelected ? .white : Kin.textQuaternary)
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
