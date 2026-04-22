import AppKit
import SwiftUI

// MARK: - Response SwiftUI view

struct InlineResponseView: View {
    @Bindable var runner: ClaudeRunner
    var agentName: String
    var onDismiss: () -> Void

    @State private var appeared = false
    @State private var copied = false

    private var responseText: String {
        runner.messages.last(where: { $0.role == .assistant })?.content ?? ""
    }

    var body: some View {
        ZStack {
            // Blur background
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()

            // Centered artifact card
            VStack(spacing: 0) {
                cardHeader
                Divider().background(Kin.border)
                cardContent
                cardFooter
            }
            .frame(maxWidth: 680, maxHeight: 520)
            .background(Kin.surface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Kin.border, lineWidth: 1))
            .shadowLg()
            .scaleEffect(appeared ? 1 : 0.94)
            .opacity(appeared ? 1 : 0)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.8).delay(0.15),
                value: appeared
            )
        }
        .onAppear { appeared = true }
    }

    private var cardHeader: some View {
        HStack(spacing: 10) {
            Text(agentName)
                .font(Kin.inter(14, weight: .semibold))
                .foregroundStyle(Kin.textPrimary)
            Spacer()
            if !responseText.isEmpty {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(responseText, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(nanoseconds: 1_500_000_000)
                        await MainActor.run { copied = false }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 12, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(Kin.inter(12))
                    }
                    .foregroundStyle(copied ? Kin.statusOnline : Kin.textTertiary)
                }
                .buttonStyle(.plain)
                .animation(.spring(response: 0.2), value: copied)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Kin.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(Kin.surfaceHover, in: Circle())
            }
            .buttonStyle(PressScaleButtonStyle(scale: 0.88))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var cardContent: some View {
        ScrollView(showsIndicators: false) {
            if runner.isStreaming && responseText.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Thinking…")
                        .font(Kin.inter(14))
                        .foregroundStyle(Kin.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            } else if let errText = runner.claudeError {
                Text(errText)
                    .font(Kin.inter(13))
                    .foregroundStyle(Kin.statusOffline)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                MarkdownText(responseText)
                    .padding(20)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var cardFooter: some View {
        HStack {
            Spacer()
            Text("Press Esc to dismiss")
                .font(Kin.inter(11))
                .foregroundStyle(Kin.textQuaternary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - Overlay window

final class InlineResponseOverlay: NSWindow {
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var dismissAction: (() -> Void)?

    init(runner: ClaudeRunner, agentName: String, onDismiss: @escaping () -> Void) {
        let screen = NSScreen.main ?? NSScreen.screens[0]

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false

        let content = InlineResponseView(
            runner: runner,
            agentName: agentName,
            onDismiss: { [weak self] in self?.animateOut(completion: onDismiss) }
        )
        let hosting = NSHostingView(rootView: content)
        hosting.frame = screen.frame
        contentView = hosting
        dismissAction = onDismiss
    }

    func present() {
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        animateIn()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                guard let self, let action = self.dismissAction else { return event }
                self.animateOut(completion: action)
                return nil
            }
            return event
        }

        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, let action = self.dismissAction else { return event }
            let clickInWindow = self.convertPoint(fromScreen: NSEvent.mouseLocation)
            let cardWidth: CGFloat = 680
            let cardHeight: CGFloat = 520
            let windowBounds = self.contentRect(forFrameRect: self.frame)
            let cardRect = CGRect(
                x: (windowBounds.width - cardWidth) / 2,
                y: (windowBounds.height - cardHeight) / 2,
                width: cardWidth,
                height: cardHeight
            )
            if !cardRect.contains(clickInWindow) {
                self.animateOut(completion: action)
                return nil
            }
            return event
        }
    }

    private func animateIn() {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.6
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 1
        }
    }

    func animateOut(completion: @escaping () -> Void) {
        if let km = keyMonitor { NSEvent.removeMonitor(km); keyMonitor = nil }
        if let cm = clickMonitor { NSEvent.removeMonitor(cm); clickMonitor = nil }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            completion()
        })
    }
}
