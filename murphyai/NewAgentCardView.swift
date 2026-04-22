import SwiftUI

// MARK: - App settings sections

private enum AppSettingsSection: Hashable {
    case general
    case appearance
    case inlineAgent

    var label: String {
        switch self {
        case .general:     return "General"
        case .appearance:  return "Appearance"
        case .inlineAgent: return "Inline Agent"
        }
    }
}

// MARK: - Global settings view (macOS Settings scene)
// Layout: 252px sidebar + 900px content = 1152px × 800px
// All spacing on 4px grid. Colors mapped to Kin tokens.

struct GlobalSettingsView: View {
    @Environment(AgentStore.self) var store
    @Environment(InlineAgentManager.self) var inlineAgent
    @Environment(\.dismiss) private var dismiss
    @State private var selection: AppSettingsSection = .general
    @AppStorage("kinTheme") private var selectedTheme = "dark"
    @AppStorage("kinClaudeModel") private var selectedModel = "sonnet"

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(width: 1152, height: 800)
        .preferredColorScheme(selectedTheme == "light" ? .light : .dark)
    }

    // MARK: - Sidebar (252px, Kin.sidebarBg = #000000 dark / #e8e8f4 light)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            profileHeader
            Rectangle().fill(Kin.border).frame(height: 1)
            appSettingsGroup
            Rectangle().fill(Kin.border).frame(height: 1)
            otherSettingsGroup
            Spacer(minLength: 0)
        }
        .frame(width: 252)
        .frame(maxHeight: .infinity)
        .background(Kin.sidebarBg)
        .overlay(alignment: .trailing) {
            Rectangle().fill(Kin.border).frame(width: 1)
        }
    }

    // Profile header: 32px avatar + "Kin" 14px semibold + "macOS" 12px at 64%
    private var profileHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Kin.accent.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(Kin.accent)
            }
            .overlay(Circle().stroke(Kin.accent.opacity(0.35), lineWidth: 1.5))

            VStack(alignment: .leading, spacing: 2) {
                Text("Kin")
                    .font(Kin.inter(14, weight: .semibold))
                    .foregroundStyle(Kin.textPrimary)
                Text("macOS")
                    .font(Kin.inter(12))
                    .foregroundStyle(Kin.textPrimary.opacity(0.64))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // "APP SETTINGS" nav group
    private var appSettingsGroup: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("APP SETTINGS")
                    .font(Kin.inter(12))
                    .foregroundStyle(Kin.textSecondary)
                Spacer()
                Text("+")
                    .font(Kin.inter(16))
                    .foregroundStyle(Kin.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 4) {
                navButton(.general)
                navButton(.appearance)
                navButton(.inlineAgent)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 16)
        }
    }

    private var otherSettingsGroup: some View {
        Text("OTHER SETTINGS")
            .font(Kin.inter(12))
            .foregroundStyle(Kin.textSecondary)
            .padding(.horizontal, 12)
            .padding(.top, 16)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Nav item: 36px tall, 4px radius, hash icon + label
    private func navButton(_ sec: AppSettingsSection) -> some View {
        Button { selection = sec } label: {
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(selection == sec ? Kin.textPrimary : Kin.textQuaternary)
                    .frame(width: 16, height: 16)
                Text(sec.label)
                    .font(Kin.inter(16))
                    .foregroundStyle(selection == sec ? Kin.textPrimary : Kin.textQuaternary)
                Spacer()
            }
            .frame(height: 36)
            .padding(.horizontal, 8)
            .background(
                selection == sec ? Kin.sidebarSelected : Color.clear,
                in: RoundedRectangle(cornerRadius: 4)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Content (900px, Kin.bg)

    private var content: some View {
        VStack(spacing: 0) {
            topBar
            Rectangle().fill(Kin.chatBorder).frame(height: 1)
            Group {
                switch selection {
                case .general:     generalPage
                case .appearance:  appearancePage
                case .inlineAgent: inlineAgentPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 900)
        .frame(maxHeight: .infinity)
        .background(Kin.bg)
    }

    // Top bar: 48px, page title left, X close right (32px touch target)
    private var topBar: some View {
        HStack {
            Text(selection.label)
                .font(Kin.inter(12))
                .foregroundStyle(Kin.textPrimary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Kin.textTertiary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(height: 48)
        .padding(.horizontal, 12)
    }

    // MARK: General page

    private var generalPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                claudeCodeSection
                dataSection
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
    }

    private var claudeCodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Code")
                .font(Kin.inter(16, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)

            HStack(spacing: 12) {
                Image(systemName: ClaudeRunner.isAvailable() ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(ClaudeRunner.isAvailable() ? Kin.statusOnline : Kin.statusOffline)

                VStack(alignment: .leading, spacing: 4) {
                    Text("CLI Status")
                        .font(Kin.inter(13, weight: .medium))
                        .foregroundStyle(Kin.textPrimary)
                    if let path = ClaudeRunner.claudePath {
                        Text(path)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Kin.textSecondary)
                    } else {
                        Text("Not found — install via npm i -g @anthropic-ai/claude-code")
                            .font(.system(size: 12))
                            .foregroundStyle(Kin.statusOffline.opacity(0.85))
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 20))
                    .foregroundStyle(Kin.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Model")
                        .font(Kin.inter(13, weight: .medium))
                        .foregroundStyle(Kin.textPrimary)
                    Text("Used by every agent and by the channel planner.")
                        .font(.system(size: 12))
                        .foregroundStyle(Kin.textSecondary)
                }

                Spacer()

                Picker("", selection: $selectedModel) {
                    Text("Sonnet 4.6").tag("sonnet")
                    Text("Opus 4.7").tag("opus")
                    Text("Haiku 4.5").tag("haiku")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
            }
            .padding(16)
            .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Data")
                .font(Kin.inter(16, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)

            HStack(spacing: 12) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Kin.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Agent data")
                        .font(Kin.inter(13, weight: .medium))
                        .foregroundStyle(Kin.textPrimary)
                    Text(store.baseDir.path)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Kin.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Button("Show in Finder") {
                    NSWorkspace.shared.open(store.baseDir)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: Appearance page

    private var appearancePage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                themeSection
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
    }

    // MARK: Inline Agent page

    private var inlineAgentPage: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                inlineAgentSection
                inlineAgentPermissionsSection
            }
            .padding(.horizontal, 36)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
    }

    private var inlineAgentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inline Agent")
                .font(Kin.inter(16, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)

            HStack(spacing: 12) {
                Image(systemName: "cursorarrow.motionlines")
                    .font(.system(size: 20))
                    .foregroundStyle(Kin.accent)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Activate with shake gesture")
                        .font(Kin.inter(13, weight: .medium))
                        .foregroundStyle(Kin.textPrimary)
                    Text("Shake cursor while dragging.")
                        .font(.system(size: 12))
                        .foregroundStyle(Kin.textSecondary)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { inlineAgent.isEnabled },
                    set: { inlineAgent.isEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            .padding(16)
            .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))

            if inlineAgent.isEnabled {
                shakeSensitivityRow
                defaultAgentRow
            }
        }
    }

    private var shakeSensitivityRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundStyle(Kin.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Shake Sensitivity")
                    .font(Kin.inter(13, weight: .medium))
                    .foregroundStyle(Kin.textPrimary)
                Text("Higher = easier to trigger.")
                    .font(.system(size: 12))
                    .foregroundStyle(Kin.textSecondary)
            }

            Spacer()

            Picker("", selection: Binding(
                get: { UserDefaults.standard.integer(forKey: "kinShakeSensitivity") == 0 ? 3
                    : UserDefaults.standard.integer(forKey: "kinShakeSensitivity") },
                set: {
                    UserDefaults.standard.set($0, forKey: "kinShakeSensitivity")
                    inlineAgent.updateSensitivity()
                }
            )) {
                Text("Low").tag(1)
                Text("Medium-Low").tag(2)
                Text("Default").tag(3)
                Text("Medium-High").tag(4)
                Text("High").tag(5)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(16)
        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private var defaultAgentRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.fill")
                .font(.system(size: 20))
                .foregroundStyle(Kin.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Default Agent")
                    .font(Kin.inter(13, weight: .medium))
                    .foregroundStyle(Kin.textPrimary)
                Text("Which agent handles inline queries.")
                    .font(.system(size: 12))
                    .foregroundStyle(Kin.textSecondary)
            }

            Spacer()

            let activeAgents = store.agents.filter { !$0.isArchived }
            Picker("", selection: Binding(
                get: { UserDefaults.standard.string(forKey: "kinInlineAgentId") ?? activeAgents.first?.id ?? "" },
                set: { UserDefaults.standard.set($0, forKey: "kinInlineAgentId") }
            )) {
                ForEach(activeAgents) { agent in
                    Text(agent.name).tag(agent.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 160)
        }
        .padding(16)
        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    private var inlineAgentPermissionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permissions")
                .font(Kin.inter(16, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)

            permissionRow(
                icon: "accessibility",
                title: "Accessibility Access",
                subtitle: "Required to read selected text from other apps.",
                isGranted: inlineAgent.accessibilityGranted,
                action: { inlineAgent.requestAccessibility() }
            )

            permissionRow(
                icon: "camera.fill",
                title: "Screen Recording",
                subtitle: "Required for screenshot capture. Prompted on first use.",
                isGranted: inlineAgent.screenRecordingGranted,
                action: {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }
            )
        }
    }

    private func permissionRow(icon: String, title: String, subtitle: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(isGranted ? Kin.statusOnline : Kin.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(Kin.inter(13, weight: .medium))
                        .foregroundStyle(Kin.textPrimary)
                    Text(isGranted ? "Granted" : "Not Granted")
                        .font(Kin.inter(11, weight: .medium))
                        .foregroundStyle(isGranted ? Kin.statusOnline : Kin.statusOffline)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            isGranted ? Kin.statusOnline.opacity(0.12) : Kin.statusOffline.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: 4)
                        )
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Kin.textSecondary)
            }

            Spacer()

            if !isGranted {
                Button("Grant Access", action: action)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(Kin.surface, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: Appearance page

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Theme")
                .font(Kin.inter(16, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)

            VStack(alignment: .leading, spacing: 12) {
                Text("Default Themes")
                    .font(Kin.inter(12, weight: .medium))
                    .foregroundStyle(Kin.textSecondary)

                HStack(alignment: .top, spacing: 16) {
                    ForEach(KinTheme.allCases, id: \.rawValue) { theme in
                        VStack(spacing: 8) {
                            ThemeSwatchCard(
                                theme: theme,
                                isSelected: selectedTheme == theme.rawValue
                            ) {
                                selectedTheme = theme.rawValue
                            }
                            Text(theme.label)
                                .font(Kin.inter(12))
                                .foregroundStyle(
                                    selectedTheme == theme.rawValue
                                        ? Kin.textPrimary
                                        : Kin.textSecondary
                                )
                        }
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Theme swatch card

private struct ThemeSwatchCard: View {
    let theme: KinTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                // Mini split preview: sidebar (left ~1/3) + content (right ~2/3)
                HStack(spacing: 0) {
                    theme.previewSidebar
                        .frame(width: 28)
                    theme.previewContent
                }
                .frame(width: 88, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(
                            isSelected ? Kin.accent : Kin.chatBorder,
                            lineWidth: isSelected ? 2 : 1
                        )
                )

                if isSelected {
                    ZStack {
                        Circle()
                            .fill(Kin.accent)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .offset(x: 8, y: -8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
