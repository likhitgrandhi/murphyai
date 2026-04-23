import AppKit
import SwiftUI

final class InlineInputPanel: NSPanel {
    private let hostingView: NSHostingView<InlineInputView>
    private var keyMonitor: Any?
    private let onDismissAction: () -> Void

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(vm: InlineInputViewModel,
         onSend: @escaping () -> Void,
         onCameraPressed: @escaping () -> Void,
         onDismiss: @escaping () -> Void,
         onFirstKey: @escaping () -> Void) {

        self.onDismissAction = onDismiss
        let content = InlineInputView(
            vm: vm,
            onSend: onSend,
            onCameraPressed: onCameraPressed,
            onDismiss: onDismiss,
            onFirstKey: onFirstKey
        )
        hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 400, height: 60)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless, .titled],
            backing: .buffered,
            defer: false
        )

        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        contentView = hostingView
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    func move(to screenPoint: CGPoint, animated: Bool) {
        let panelWidth: CGFloat = 400
        let panelHeight = hostingView.fittingSize.height.clamped(to: 56...300)
        var origin = CGPoint(x: screenPoint.x + 14, y: screenPoint.y - panelHeight - 14)

        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            origin.x = Swift.min(origin.x, vis.maxX - panelWidth - 8)
            origin.x = Swift.max(origin.x, vis.minX + 8)
            origin.y = Swift.min(origin.y, vis.maxY - panelHeight - 8)
            origin.y = Swift.max(origin.y, vis.minY + 8)
        }

        let newFrame = NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight))
        setFrame(newFrame, display: true, animate: false)
    }

    func show(at point: CGPoint) {
        move(to: point, animated: false)
        alphaValue = 0
        orderFrontRegardless()
        makeKey()

        // Focus the text field after the hosting view's first layout.
        DispatchQueue.main.async { [weak self] in
            self?.focusTextField()
        }

        // Local key monitor for Esc (belt-and-suspenders; TextField coordinator also handles it)
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.onDismissAction()
                return nil
            }
            return event
        }

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    private func focusTextField() {
        guard let contentView = contentView else { return }
        if let field = findTextField(in: contentView) {
            makeFirstResponder(field)
        }
    }

    private func findTextField(in view: NSView) -> NSTextField? {
        if let tf = view as? NSTextField { return tf }
        for sub in view.subviews {
            if let found = findTextField(in: sub) { return found }
        }
        return nil
    }

    func hide(completion: @escaping () -> Void = {}) {
        if let km = keyMonitor { NSEvent.removeMonitor(km); keyMonitor = nil }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
            completion()
        })
    }
}

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
