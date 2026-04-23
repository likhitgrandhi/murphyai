import SwiftUI

struct NewAgentSheet: View {
    @Environment(AgentStore.self) var store
    @Environment(\.dismiss) private var dismiss

    let editingAgent: AgentConfig?

    @State private var activeTab: SheetTab = .templates
    @State private var name = ""
    @State private var role = ""
    @State private var icon = "person.fill"
    @State private var tint = "#7BA4FF"
    @State private var systemPrompt = ""
    @State private var skills: [String] = []
    @State private var newSkill = ""

    private var isEditing: Bool { editingAgent != nil }
    private var tintColor: Color { Color(hex: tint) ?? Kin.accent }

    enum SheetTab { case templates, blank }

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader
            if !isEditing {
                tabPicker
            }
            Divider().opacity(0.4)
            if isEditing || activeTab == .blank {
                blankForm
            } else {
                templateGallery
            }
        }
        .frame(width: 540)
        .background(Color(red: 0.09, green: 0.088, blue: 0.094))
        .onAppear { populateFromExisting() }
    }

    // MARK: - Header

    private var sheetHeader: some View {
        HStack {
            Text(isEditing ? "Edit Agent" : "Hire Agent")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Kin.textPrimary)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabButton("Templates", tab: .templates)
            tabButton("Custom", tab: .blank)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
    }

    private func tabButton(_ label: String, tab: SheetTab) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { activeTab = tab }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: activeTab == tab ? .medium : .regular))
                .foregroundStyle(activeTab == tab ? Kin.textPrimary : Kin.textSecondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 18)
        .overlay(alignment: .bottom) {
            if activeTab == tab {
                Rectangle()
                    .fill(Kin.accent)
                    .frame(height: 2)
                    .offset(y: 2)
            }
        }
    }

    // MARK: - Template gallery

    private var templateGallery: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
            ], spacing: 10) {
                ForEach(AgentConfig.templates) { template in
                    TemplateCard(template: template) {
                        applyTemplate(template)
                        withAnimation(.easeOut(duration: 0.15)) { activeTab = .blank }
                    }
                }
            }
            .padding(20)
        }
        .frame(height: 400)
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

                    formField("Role") {
                        TextField("One-line description", text: $role)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack(spacing: 12) {
                        formField("Icon (SF Symbol)") {
                            TextField("hammer.fill", text: $icon)
                                .textFieldStyle(.roundedBorder)
                        }
                        formField("Tint (hex)") {
                            TextField("#7BA4FF", text: $tint)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    formField("System Prompt") {
                        TextEditor(text: $systemPrompt)
                            .frame(height: 80)
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
                }
                .padding(20)
            }
            .frame(height: 400)

            Divider().opacity(0.4)
            formFooter
        }
    }

    private var agentPreviewRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(white: 0.16))
                    .frame(width: 40, height: 40)
                Image(systemName: icon.isEmpty ? "person.fill" : icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(white: 0.72))
            }
            .overlay(Circle().stroke(tintColor, lineWidth: 2))

            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Agent name" : name)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(name.isEmpty ? Kin.textTertiary : Kin.textPrimary)
                Text(role.isEmpty ? "Role" : role)
                    .font(.system(size: 11))
                    .foregroundStyle(role.isEmpty ? Kin.textTertiary : Kin.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 10))
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
            Button(isEditing ? "Save Changes" : "Create Agent") {
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

    private func applyTemplate(_ template: AgentConfig.Template) {
        name = template.name
        role = template.role
        icon = template.icon
        tint = template.tint
        systemPrompt = template.systemPrompt
        skills = template.skills
    }

    private func populateFromExisting() {
        guard let agent = editingAgent else { return }
        name = agent.name
        role = agent.role
        icon = agent.icon
        tint = agent.tint
        systemPrompt = agent.systemPrompt
        skills = agent.skills
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
            skills: skills
        ))
    }
}

// MARK: - Template card

private struct TemplateCard: View {
    let template: AgentConfig.Template
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.16))
                        .frame(width: 36, height: 36)
                    Image(systemName: template.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color(white: 0.72))
                }
                .overlay(Circle().stroke(Color(hex: template.tint) ?? Kin.accent, lineWidth: 1.5))

                VStack(spacing: 2) {
                    Text(template.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Kin.textPrimary)
                        .lineLimit(1)
                    Text(template.role.components(separatedBy: " · ").last ?? "")
                        .font(.system(size: 10))
                        .foregroundStyle(Kin.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color(white: 0.13), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(white: 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(PressScaleButtonStyle(scale: 0.96))
    }
}
