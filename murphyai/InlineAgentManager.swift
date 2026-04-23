import AppKit
import Observation

@Observable
@MainActor
final class InlineAgentManager {
    var accessibilityGranted = false
    var screenRecordingGranted = false
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "kinInlineAgentEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "kinInlineAgentEnabled") }
    }

    private var shakeDetector = ShakeDetector()
    private var globalMonitor: Any?
    private var followMonitor: Any?

    private var inputPanel: InlineInputPanel?
    private var regionPicker: ScreenRegionPicker?
    private var responseOverlay: InlineResponseOverlay?
    private var vm = InlineInputViewModel()
    private var activeAgent: AgentConfig?
    private var panelAnchoredToCursor = true
    private weak var runnerStore: RunnerStore?
    private weak var agentStore: AgentStore?
    private var pendingWatch: Task<Void, Never>?
    private var previousApp: NSRunningApplication?

    // MARK: - Bootstrap

    func bootstrap(store: AgentStore, runnerStore: RunnerStore) {
        self.agentStore = store
        self.runnerStore = runnerStore
        checkPermissions()
        updateSensitivity()
        installGlobalMonitor(store: store)

        UserDefaults.standard.register(defaults: ["kinInlineAgentEnabled": true])
    }

    func teardown() {
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let m = followMonitor { NSEvent.removeMonitor(m); followMonitor = nil }
        inputPanel?.orderOut(nil)
        responseOverlay?.orderOut(nil)
    }

    // MARK: - Sensitivity

    func updateSensitivity() {
        let raw = UserDefaults.standard.integer(forKey: "kinShakeSensitivity")
        let level = raw == 0 ? 3 : max(1, min(5, raw))
        shakeDetector.minReverseCount = 6 - level  // level 5 → 1 flip, level 1 → 5 flips
    }

    // MARK: - Permissions

    func checkPermissions() {
        accessibilityGranted = AccessibilityHelper.isGranted()
        // Screen recording status is only reliably knowable after an actual attempt.
        // We mark it as true here and let the OS prompt on first use.
        screenRecordingGranted = true
    }

    func requestAccessibility() {
        AccessibilityHelper.requestAccess()
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            accessibilityGranted = AccessibilityHelper.isGranted()
        }
    }

    // MARK: - Global monitor

    private func installGlobalMonitor(store: AgentStore) {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseMoved(event: event, store: store)
            }
        }
    }

    private func handleMouseMoved(event: NSEvent, store: AgentStore) {
        guard isEnabled, inputPanel == nil, responseOverlay == nil else { return }
        let point = NSEvent.mouseLocation
        let time = event.timestamp
        if let firePoint = shakeDetector.record(point: point, at: time) {
            handleShake(at: firePoint, store: store)
        }
    }

    // MARK: - Shake handling

    private func handleShake(at point: CGPoint, store: AgentStore) {
        accessibilityGranted = AccessibilityHelper.isGranted()
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost?.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }
        let selectedText = AccessibilityHelper.selectedTextFromFrontmostApp()
        let agent = resolveAgent(from: store)
        showInputPanel(at: point, selectedText: selectedText, agent: agent)
    }

    private func restorePreviousApp() {
        previousApp?.activate(options: [])
    }

    private func resolveAgent(from store: AgentStore) -> AgentConfig {
        let savedId = UserDefaults.standard.string(forKey: "kinInlineAgentId")
        let active = store.agents.filter { !$0.isArchived }
        return active.first(where: { $0.id == savedId }) ?? active.first ?? AgentConfig.defaultAgents[0]
    }

    // MARK: - Input panel lifecycle

    private func showInputPanel(at point: CGPoint, selectedText: String?, agent: AgentConfig) {
        activeAgent = agent
        vm = InlineInputViewModel()
        vm.selectedText = selectedText

        let panel = InlineInputPanel(
            vm: vm,
            onSend: { [weak self] in self?.sendToAgent() },
            onCameraPressed: { [weak self] in self?.beginScreenCapture() },
            onDismiss: { [weak self] in self?.dismiss() },
            onFirstKey: { [weak self] in
                self?.panelAnchoredToCursor = false
                self?.stopFollowMonitor()
            }
        )
        inputPanel = panel
        panelAnchoredToCursor = false
        panel.show(at: point)
    }

    private func startFollowMonitor() {}
    private func stopFollowMonitor() {
        if let m = followMonitor { NSEvent.removeMonitor(m); followMonitor = nil }
    }

    // MARK: - Screenshot capture

    func beginScreenCapture() {
        guard let panel = inputPanel, let screen = NSScreen.main else { return }
        stopFollowMonitor()
        panelAnchoredToCursor = false
        panel.alphaValue = 0
        panel.orderOut(nil)

        let picker = ScreenRegionPicker(screen: screen)
        picker.onCapture = { [weak self] cgImage in
            Task { @MainActor [weak self] in
                self?.finishCapture(image: cgImage)
            }
        }
        picker.onCancel = { [weak self] in
            Task { @MainActor [weak self] in
                self?.restorePanel()
            }
        }
        regionPicker = picker
        picker.present()
    }

    private func finishCapture(image: CGImage) {
        regionPicker = nil
        vm.capturedImage = image
        restorePanel()
    }

    private func restorePanel() {
        guard let panel = inputPanel else { return }
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    // MARK: - Send

    private func sendToAgent() {
        guard let agent = activeAgent,
              let store = agentStore,
              let runnerStore = runnerStore else { return }
        let text = vm.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var prompt = text
        if let sel = vm.selectedText {
            prompt += "\n\n[Selected text from screen:\n\(sel)]"
        }
        if let image = vm.capturedImage, let path = saveImageToTemp(image) {
            prompt += "\n\n[User attached a screenshot at: \(path). Use the Read tool on that path to view and analyze it.]"
        }

        let runner = runnerStore.runner(for: agent, store: store)
        stopFollowMonitor()
        inputPanel?.hide { [weak self] in
            Task { @MainActor [weak self] in
                self?.inputPanel = nil
                self?.restorePreviousApp()
            }
        }

        let baseline = runner.messages.count
        runner.send(userMessage: prompt, agent: agent, memoryContent: store.memoryContent(for: agent))
        watchForResponse(runner: runner, agentName: agent.name, baseline: baseline)
    }

    private func watchForResponse(runner: ClaudeRunner, agentName: String, baseline: Int) {
        pendingWatch?.cancel()
        pendingWatch = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                if !runner.isStreaming {
                    if let last = runner.messages.last,
                       runner.messages.count > baseline,
                       last.role == .assistant,
                       !last.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self?.showResponseOverlay(runner: runner, agentName: agentName)
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    // MARK: - Response overlay

    private func showResponseOverlay(runner: ClaudeRunner, agentName: String) {
        let overlay = InlineResponseOverlay(runner: runner, agentName: agentName) { [weak self] in
            Task { @MainActor [weak self] in
                self?.cleanup()
            }
        }
        responseOverlay = overlay
        overlay.present()
    }

    // MARK: - Dismiss / cleanup

    func dismiss() {
        stopFollowMonitor()
        inputPanel?.hide { [weak self] in
            Task { @MainActor [weak self] in
                self?.inputPanel = nil
                self?.restorePreviousApp()
            }
        }
    }

    private func saveImageToTemp(_ image: CGImage) -> String? {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { return nil }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kin-inline", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("screenshot-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
            return url.path
        } catch { return nil }
    }

    private func cleanup() {
        pendingWatch?.cancel()
        pendingWatch = nil
        responseOverlay = nil
        inputPanel = nil
        activeAgent = nil
        vm = InlineInputViewModel()
        restorePreviousApp()
        previousApp = nil
    }
}
