import AppKit
import SwiftUI
import ScreenCaptureKit

// MARK: - Picker overlay SwiftUI view

private struct PickerOverlayView: View {
    var onCapture: (CGRect) -> Void
    var onCancel: () -> Void

    @State private var dragStart: CGPoint = .zero
    @State private var dragCurrent: CGPoint = .zero
    @State private var isDragging = false

    private var selectionRect: CGRect {
        CGRect(
            x: Swift.min(dragStart.x, dragCurrent.x),
            y: Swift.min(dragStart.y, dragCurrent.y),
            width: abs(dragCurrent.x - dragStart.x),
            height: abs(dragCurrent.y - dragStart.y)
        )
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.opacity(0.4)

                if isDragging && selectionRect.width > 4 && selectionRect.height > 4 {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: selectionRect.width, height: selectionRect.height)
                        .overlay(Rectangle().stroke(Color.white, lineWidth: 1.5))
                        .position(x: selectionRect.midX, y: selectionRect.midY)
                }

                Text("Drag to capture • Esc to cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 40)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .local)
                    .onChanged { value in
                        if !isDragging {
                            dragStart = value.startLocation
                            isDragging = true
                        }
                        dragCurrent = value.location
                    }
                    .onEnded { value in
                        isDragging = false
                        let rect = CGRect(
                            x: Swift.min(dragStart.x, value.location.x),
                            y: Swift.min(dragStart.y, value.location.y),
                            width: abs(value.location.x - dragStart.x),
                            height: abs(value.location.y - dragStart.y)
                        )
                        if rect.width > 10 && rect.height > 10 {
                            onCapture(rect)
                        } else {
                            onCancel()
                        }
                    }
            )
        }
        .onAppear { NSCursor.crosshair.push() }
        .onDisappear { NSCursor.pop() }
    }
}

// MARK: - Screen region picker window

final class ScreenRegionPicker: NSWindow {
    var onCapture: ((CGImage) -> Void)?
    var onCancel: (() -> Void)?

    private let targetScreen: NSScreen
    private var keyMonitor: Any?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(screen: NSScreen) {
        self.targetScreen = screen

        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)) - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false

        let overlay = PickerOverlayView(
            onCapture: { [weak self] viewRect in
                self?.captureRegion(viewRect: viewRect)
            },
            onCancel: { [weak self] in
                self?.dismiss()
                self?.onCancel?()
            }
        )
        contentView = NSHostingView(rootView: overlay)
    }

    func present() {
        alphaValue = 0
        orderFrontRegardless()
        makeKey()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().alphaValue = 1
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                self?.dismiss()
                self?.onCancel?()
                return nil
            }
            return event
        }
    }

    func dismiss() {
        if let km = keyMonitor { NSEvent.removeMonitor(km); keyMonitor = nil }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            animator().alphaValue = 0
        }, completionHandler: {
            self.orderOut(nil)
        })
    }

    private func captureRegion(viewRect: CGRect) {
        dismiss()

        // Convert view-local rect (SwiftUI top-left) to AppKit screen coords (bottom-left)
        let screenHeight = targetScreen.frame.height
        let screenRect = CGRect(
            x: targetScreen.frame.origin.x + viewRect.origin.x,
            y: targetScreen.frame.origin.y + (screenHeight - viewRect.origin.y - viewRect.height),
            width: viewRect.width,
            height: viewRect.height
        )

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first else { return }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.sourceRect = screenRect
                config.width = Swift.max(1, Int(screenRect.width * 2))
                config.height = Swift.max(1, Int(screenRect.height * 2))
                config.scalesToFit = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                await MainActor.run { self.onCapture?(image) }
            } catch {
                // Silently fail — user will see no image pill
            }
        }
    }
}
