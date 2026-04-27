import SwiftUI
import AppKit

// Drives the two-step email → OTP flow.
// Shows OTPEntryView once SessionStore.pendingEmail is set by EmailEntryView.
// Locks the window to a fixed size while auth is active so the illustrated
// background doesn't stretch or crop unexpectedly during resize.
struct AuthFlowView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        Group {
            if session.pendingEmail != nil {
                OTPEntryView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            } else {
                EmailEntryView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .onAppear  { setResizable(false) }
        .onDisappear { setResizable(true) }
    }

    private func setResizable(_ resizable: Bool) {
        guard let window = NSApp.windows.first else { return }
        if resizable {
            window.styleMask.insert(.resizable)
        } else {
            window.styleMask.remove(.resizable)
            window.setContentSize(NSSize(width: 1060, height: 680))
        }
    }
}
