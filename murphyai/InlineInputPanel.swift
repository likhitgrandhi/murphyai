import AppKit
import SwiftUI

final class InlineInputPanel: NSPanel {
    private let hostingView: NSHostingView<InlineInputView>

    init(vm: InlineInputViewModel,
         onSend: @escaping () -> Void,
         onCameraPressed: @escaping () -> Void,
         onDismiss: @escaping () -> Void,
         onFirstKey: @escaping () -> Void) {

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
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        contentView = hostingView
        isReleasedWhenClosed = false
    }

    func move(to screenPoint: CGPoint, animated: Bool) {
        let panelWidth: CGFloat = 400
        let panelHeight = hostingView.fittingSize.height.clamped(to: 56...300)
        var origin = CGPoint(x: screenPoint.x + 14, y: screenPoint.y - panelHeight - 14)

        if let screen = NSScreen.main {
            let vis = screen.visibleFrame
            origin.x = min(origin.x, vis.maxX - panelWidth - 8)
            origin.x = max(origin.x, vis.minX + 8)
            origin.y = min(origin.y, vis.maxY - panelHeight - 8)
            origin.y = max(origin.y, vis.minY + 8)
        }

        let newFrame = NSRect(origin: origin, size: NSSize(width: panelWidth, height: panelHeight))

        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.08
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(newFrame, display: true)
            }
        } else {
            setFrame(newFrame, display: false)
        }
    }

    func show(at point: CGPoint) {
        move(to: point, animated: false)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func hide(completion: @escaping () -> Void = {}) {
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
