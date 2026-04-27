import SwiftUI

struct NewAgentSheet: View {
    @Environment(AgentStore.self) var store
    @Environment(\.dismiss) private var dismiss

    let editingAgent: AgentConfig?

    enum SheetMode { case pick, describe, form }
    @State private var mode: SheetMode = .pick

    // Agent state
    @State private var name = ""
    @State private var role = ""
    @State private var icon = "person.fill"
    @State private var tint = "#7BA4FF"
    @State private var systemPrompt = ""
    @State private var skills: [String] = []
    @State private var newSkill = ""
    @State private var folderPaths: [String] = []
    @State private var newFolderPath = ""
    @State private var avatarPath: String?

    // Describe-screen state
    @State private var description = ""
    @State private var isGenerating = false
    @State private var generationError: String?

    private var isEditing: Bool { editingAgent != nil }
    private var tintColor: Color { Color(hex: tint) ?? Kin.accent }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            Divider().opacity(0.3)
            switch mode {
            case .pick:     pickerContent
            case .describe: describeScreen
            case .form:     blankForm
            }
        }
        .frame(width: 540)
        .background(Kin.bg)
        .onAppear {
            populateFromExisting()
            if isEditing { mode = .form }
        }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        ZStack(alignment: .center) {
            HStack {
                if !isEditing && mode != .pick {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { mode = .pick }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Kin.textSecondary)
                            .frame(width: 26, height: 26)
                            .background(Kin.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Kin.textSecondary)
                        .frame(width: 26, height: 26)
                        .background(Kin.surface, in: Circle())
                }
                .buttonStyle(.plain)
            }

            if isEditing || mode == .form {
                Text(isEditing ? "Edit Agent" : "Customize Agent")
                    .font(Kin.inter(14, weight: .medium))
                    .foregroundStyle(Kin.textPrimary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Picker

    private var pickerContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 6) {
                    Text("Hire an Agent")
                        .font(Kin.inter(22, weight: .bold))
                        .foregroundStyle(Kin.textPrimary)
                    Text("Pick a specialist or start from a blank slate.")
                        .font(Kin.inter(13))
                        .foregroundStyle(Kin.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 24)
                .padding(.horizontal, 24)

                VStack(spacing: 0) {
                    pickerRow(
                        icon: "pencil.and.scribble",
                        tintHex: "#949CF7",
                        name: "Build From Scratch",
                        description: "Describe what you need — we'll do the rest"
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) { mode = .describe }
                    }
                }
                .padding(.horizontal, 20)

                VStack(alignment: .leading, spacing: 6) {
                    Text("START FROM A TEMPLATE")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Kin.textTertiary)
                        .kerning(0.5)
                        .padding(.top, 22)
                        .padding(.bottom, 4)

                    ForEach(AgentConfig.templates) { template in
                        pickerRow(
                            icon: template.icon,
                            tintHex: template.tint,
                            name: template.name,
                            description: template.role.components(separatedBy: " · ").last ?? template.role
                        ) {
                            applyTemplate(template)
                            withAnimation(.easeOut(duration: 0.15)) { mode = .form }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(maxHeight: 520)
    }

    @ViewBuilder
    private func pickerRow(
        icon: String,
        tintHex: String,
        name: String,
        description: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Kin.avatarBg)
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(Color(hex: tintHex) ?? Kin.accent)
                }
                .overlay(
                    Circle().stroke(
                        (Color(hex: tintHex) ?? Kin.accent).opacity(0.4),
                        lineWidth: 1.5
                    )
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(Kin.inter(13, weight: .medium))
                        .foregroundStyle(Kin.textPrimary)
                    Text(description)
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Kin.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Kin.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Kin.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.98))
        .padding(.bottom, 6)
    }

    // MARK: - Describe screen

    private var describeScreen: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("Create an Agent")
                            .font(Kin.inter(22, weight: .bold))
                            .foregroundStyle(Kin.textPrimary)
                        Text("What should this agent do? Describe its role, tasks, and how it should behave. The more specific you are, the better it performs.")
                            .font(Kin.inter(13))
                            .foregroundStyle(Kin.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    descriptionEditor

                    if let err = generationError {
                        Text(err)
                            .font(Kin.inter(12))
                            .foregroundStyle(Color(hex: "#FF7B7B") ?? .red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(height: 440)

            Divider().opacity(0.4)

            Button {
                Task { await generateAgent() }
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(isGenerating ? "Generating…" : "Create")
                        .font(Kin.inter(14, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    (canGenerate ? Kin.accent : Kin.accent.opacity(0.4)),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.98))
            .disabled(!canGenerate)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var canGenerate: Bool {
        !isGenerating && description.trimmingCharacters(in: .whitespaces).count >= 5
    }

    private var descriptionEditor: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Kin.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Kin.border, lineWidth: 0.5)
                )

            if description.isEmpty {
                Text("e.g. An agent that writes friendly marketing copy for our SaaS landing page.")
                    .font(Kin.inter(13))
                    .foregroundStyle(Kin.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }

            TextEditor(text: $description)
                .font(Kin.inter(13))
                .foregroundStyle(Kin.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onChange(of: description) { _, newValue in
                    if newValue.count > 200 {
                        description = String(newValue.prefix(200))
                    }
                }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text("\(description.count)/200")
                        .font(Kin.inter(11))
                        .foregroundStyle(Kin.textTertiary)
                        .padding(.trailing, 12)
                        .padding(.bottom, 8)
                }
            }
        }
        .frame(height: 260)
    }

    @MainActor
    private func generateAgent() async {
        generationError = nil
        isGenerating = true
        defer { isGenerating = false }

        do {
            let generated = try await AgentGenerator.generate(
                description: description.trimmingCharacters(in: .whitespaces)
            )
            name = generated.name
            role = generated.role
            systemPrompt = generated.systemPrompt
            skills = generated.skills
            folderPaths = generated.folderPaths

            // Fetch pixabot avatar keyed by the generated name
            let avatarFile = store.avatarsDir
                .appendingPathComponent("\(PixabotAvatar.id(for: generated.name)).png")
            if let path = await PixabotAvatar.downloadAvatar(for: generated.name, to: avatarFile) {
                avatarPath = path
            }

            withAnimation(.easeOut(duration: 0.18)) { mode = .form }
        } catch {
            generationError = error.localizedDescription
        }
    }

    // MARK: - Blank form

    private var blankForm: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    agentPreviewRow

                    formField("Name") {
                        TextField("e.g. Alex, Reviewer…", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    formField("About") {
                        TextField("One-line description", text: $role)
                            .textFieldStyle(.roundedBorder)
                    }

                    formField("System Prompt") {
                        TextEditor(text: $systemPrompt)
                            .frame(height: 120)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .background(Kin.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    formField("Skills") {
                        VStack(alignment: .leading, spacing: 6) {
                            if !skills.isEmpty {
                                FlowLayout(spacing: 6) {
                                    ForEach(skills, id: \.self) { skill in
                                        HStack(spacing: 4) {
                                            Text(skill)
                                                .font(.system(size: 11))
                                                .foregroundStyle(Kin.textSecondary)
                                            Button {
                                                skills.removeAll { $0 == skill }
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundStyle(Kin.textTertiary)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                            HStack(spacing: 6) {
                                TextField("Add skill…", text: $newSkill)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .onSubmit { addSkill() }
                                Button("Add") { addSkill() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Kin.accent)
                                    .controlSize(.small)
                                    .disabled(newSkill.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }

                    formField("Folder Access") {
                        VStack(alignment: .leading, spacing: 6) {
                            if !folderPaths.isEmpty {
                                VStack(spacing: 4) {
                                    ForEach(folderPaths, id: \.self) { path in
                                        HStack(spacing: 8) {
                                            Image(systemName: "folder")
                                                .font(.system(size: 11))
                                                .foregroundStyle(Kin.textSecondary)
                                            Text(path)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Kin.textSecondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Spacer()
                                            Button {
                                                folderPaths.removeAll { $0 == path }
                                            } label: {
                                                Image(systemName: "trash")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(Color(hex: "#FF7B7B") ?? .red)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }
                            }
                            HStack(spacing: 6) {
                                TextField("/Users/you/project", text: $newFolderPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12))
                                    .onSubmit { addFolderPath() }
                                Button("Add") { addFolderPath() }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Kin.accent)
                                    .controlSize(.small)
                                    .disabled(newFolderPath.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .frame(height: 400)

            Divider().opacity(0.4)
            formFooter
        }
    }

    private var agentPreviewRow: some View {
        HStack(spacing: 14) {
            AgentAvatarCircle(
                name: name.isEmpty ? "Agent" : name,
                tint: tint,
                size: 44,
                avatarPath: avatarPath
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Agent name" : name)
                    .font(Kin.inter(13, weight: .medium))
                    .foregroundStyle(name.isEmpty ? Kin.textTertiary : Kin.textPrimary)
                Text(role.isEmpty ? "About" : role)
                    .font(Kin.inter(11))
                    .foregroundStyle(role.isEmpty ? Kin.textTertiary : Kin.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Kin.border, lineWidth: 0.5)
        )
    }

    private var formFooter: some View {
        HStack(spacing: 10) {
            if isEditing {
                Button("Delete", role: .destructive) {
                    if let agent = editingAgent { store.delete(agent) }
                    dismiss()
                }
                .foregroundStyle(.red.opacity(0.7))
                .buttonStyle(.plain)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(Kin.textSecondary)
            Button(isEditing ? "Save Changes" : "Hire Agent") {
                commitAgent()
                dismiss()
            }
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            .buttonStyle(.borderedProminent)
            .tint(Kin.accent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Field builder

    @ViewBuilder
    private func formField<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Kin.textTertiary)
            content()
        }
    }

    // MARK: - Data helpers

    private func addSkill() {
        let trimmed = newSkill.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !skills.contains(trimmed) else { return }
        skills.append(trimmed)
        newSkill = ""
    }

    private func addFolderPath() {
        let trimmed = newFolderPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !folderPaths.contains(trimmed) else { return }
        folderPaths.append(trimmed)
        newFolderPath = ""
    }

    private func applyTemplate(_ template: AgentConfig.Template) {
        name = template.name
        role = template.role
        icon = template.icon
        tint = template.tint
        systemPrompt = template.systemPrompt
        skills = template.skills
        folderPaths = []
        avatarPath = nil
    }

    private func populateFromExisting() {
        guard let agent = editingAgent else { return }
        name = agent.name
        role = agent.role
        icon = agent.icon
        tint = agent.tint
        systemPrompt = agent.systemPrompt
        skills = agent.skills
        folderPaths = agent.folderPaths
        avatarPath = agent.avatarPath
    }

    private func commitAgent() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let slug = editingAgent?.id ?? trimmed
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-")).inverted)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        store.save(AgentConfig(
            id: slug.isEmpty ? UUID().uuidString : slug,
            name: trimmed,
            role: role.trimmingCharacters(in: .whitespaces),
            icon: icon.isEmpty ? "person.fill" : icon,
            tint: tint.isEmpty ? "#7BA4FF" : tint,
            systemPrompt: systemPrompt,
            skills: skills,
            folderPaths: folderPaths,
            avatarPath: avatarPath
        ))
    }
}
