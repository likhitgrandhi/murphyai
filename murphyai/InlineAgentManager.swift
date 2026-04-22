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
    private var ephemeralRunner: ClaudeRunner?
    private var activeAgent: AgentConfig?
    private var panelAnchoredToCursor = true

    // MARK: - Bootstrap

    func bootstrap(store: AgentStore) {
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
            guard let self else { return }
            Task { @MainActor in
                self.handleMouseMoved(event: event, store: store)
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
        let selectedText = accessibilityGranted ? AccessibilityHelper.selectedTextFromFrontmostApp() : nil
        let agent = resolveAgent(from: store)
        showInputPanel(at: point, selectedText: selectedText, agent: agent)
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
        panelAnchoredToCursor = true
        panel.show(at: point)
        startFollowMonitor()
    }

    private func startFollowMonitor() {
        followMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            guard let self else { return }
            Task { @MainActor in
                guard self.panelAnchoredToCursor, let panel = self.inputPanel else { return }
                panel.move(to: NSEvent.mouseLocation, animated: true)
            }
        }
    }

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
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    // MARK: - Send

    private func sendToAgent() {
        guard let agent = activeAgent else { return }
        let text = vm.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var prompt = text
        if let sel = vm.selectedText {
            prompt += "\n\n[Selected text from screen:\n\(sel)]"
        }
        if vm.capturedImage != nil {
            prompt += "\n\n[User attached a screenshot — describe or analyze what you see if asked]"
        }

        let runner = ClaudeRunner(conversationURL: nil)
        ephemeralRunner = runner
        inputPanel?.hide()
        stopFollowMonitor()

        runner.send(userMessage: prompt, agent: agent, memoryContent: "")
        showResponseOverlay(runner: runner, agentName: agent.name)
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
            }
        }
    }

    private func cleanup() {
        responseOverlay = nil
        ephemeralRunner = nil
        inputPanel = nil
        activeAgent = nil
        vm = InlineInputViewModel()
    }
}
