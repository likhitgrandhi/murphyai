import SwiftUI

struct NewChannelSheet: View {
    @Environment(AgentStore.self) var store
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var topic = ""
    @State private var memberIds: Set<String> = []
    @State private var folderPaths: [String] = []

    private var slug: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
    }

    private var canCreate: Bool {
        !slug.isEmpty && !memberIds.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().opacity(0.4)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    nameField
                    topicField
                    membersField
                    foldersField
                }
                .padding(24)
            }
            Divider().opacity(0.4)
            sheetFooter
        }
        .frame(width: 440)
        .background(Color(white: 0.11))
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("New Channel")
                    .font(Kin.inter(15, weight: .semibold))
                    .foregroundStyle(Kin.textPrimary)
                Text("Create a group workspace for your agents")
                    .font(Kin.inter(12))
                    .foregroundStyle(Kin.textSecondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Kin.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Kin.surface, in: Circle())
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    // MARK: - Form fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            formLabel("Channel name")
            HStack(spacing: 6) {
                Text("#")
                    .font(Kin.inter(13, weight: .medium))
                    .foregroundStyle(Kin.textSecondary)
                TextField("e.g. design-review", text: $name)
                    .textFieldStyle(.plain)
                    .font(Kin.inter(13))
                    .foregroundStyle(Kin.textPrimary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Kin.border, lineWidth: 1))
        }
    }

    private var topicField: some View {
        VStack(alignment: .leading, spacing: 7) {
            formLabel("Topic (optional)")
            TextField("What is this channel for?", text: $topic)
                .textFieldStyle(.plain)
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Kin.border, lineWidth: 1))
        }
    }

    private var membersField: some View {
        VStack(alignment: .leading, spacing: 10) {
            formLabel("Add agents")
            if store.activeAgents.isEmpty {
                Text("No agents yet. Create an agent first.")
                    .font(Kin.inter(12))
                    .foregroundStyle(Kin.textTertiary)
            } else {
                VStack(spacing: 2) {
                    ForEach(store.activeAgents) { agent in
                        let selected = memberIds.contains(agent.id)
                        Button {
                            if selected { memberIds.remove(agent.id) }
                            else { memberIds.insert(agent.id) }
                        } label: {
                            HStack(spacing: 10) {
                                AgentAvatarCircle(name: agent.name, tint: agent.tint, size: 26)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(agent.name)
                                        .font(Kin.inter(13, weight: .medium))
                                        .foregroundStyle(Kin.textPrimary)
                                    Text(agent.role)
                                        .font(Kin.inter(11))
                                        .foregroundStyle(Kin.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16, weight: .regular))
                                    .foregroundStyle(selected ? Kin.accent : Kin.border)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                selected ? Kin.surface : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressScaleButtonStyle(scale: 0.98))
                    }
                }
                .padding(6)
                .background(Color(white: 0.09), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Kin.border, lineWidth: 1))
            }
        }
    }

    private var foldersField: some View {
        VStack(alignment: .leading, spacing: 10) {
            formLabel("Folder access (optional)")
            if !folderPaths.isEmpty {
                VStack(spacing: 3) {
                    ForEach(folderPaths, id: \.self) { path in
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.system(size: 11))
                                .foregroundStyle(Kin.textTertiary)
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Kin.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button { folderPaths.removeAll { $0 == path } } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Kin.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Button("Add Folder…") { pickFolder() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .font(Kin.inter(12))
        }
    }

    // MARK: - Footer

    private var sheetFooter: some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .font(Kin.inter(13))
            Button("Create Channel") { createChannel() }
                .keyboardShortcut(.defaultAction)
                .font(Kin.inter(13, weight: .medium))
                .buttonStyle(.borderedProminent)
                .tint(Kin.accent)
                .disabled(!canCreate)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Actions

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            if !folderPaths.contains(url.path) { folderPaths.append(url.path) }
        }
    }

    private func createChannel() {
        let channel = Channel(
            id: UUID().uuidString,
            name: slug,
            topic: topic.trimmingCharacters(in: .whitespacesAndNewlines),
            memberAgentIds: Array(memberIds),
            folderPaths: folderPaths
        )
        store.saveChannel(channel)
        dismiss()
    }

    private func formLabel(_ text: String) -> some View {
        Text(text)
            .font(Kin.inter(11, weight: .semibold))
            .foregroundStyle(Kin.textSecondary)
            .tracking(0.4)
    }
}
