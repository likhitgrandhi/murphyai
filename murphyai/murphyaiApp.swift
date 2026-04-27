import SwiftUI
import AppKit
import CoreText

@main
struct KinApp: App {
    @State private var session = SessionStore()
    @State private var workspaceStore = WorkspaceStore()
    @AppStorage("kinTheme") private var kinTheme = "dark"

    // Pending deep-link code: stored in memory if a kin:// link arrives
    // before the user is signed in. Cleared after the join preview is shown.
    @State private var pendingInviteCode: String?
    // Live preview result from a deep link, forwarded into the active flow.
    @State private var pendingInvitePreview: InvitePreview?

    // Tracks the in-flight refresh so a rapid sign-out → sign-in-as-other-user
    // sequence doesn't let the previous account's workspace list clobber the
    // current account's.
    @State private var refreshTask: Task<Void, Never>?

    init() {
        registerInterFont()
        registerFigtreeFont()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                rootView
            }
            .animation(.easeInOut(duration: 0.2), value: animationKey)
            .preferredColorScheme(kinTheme == "light" ? .light : .dark)
            .onAppear {
                applyAppearance(kinTheme)
                Task { await bootstrap() }
            }
            .onChange(of: kinTheme) { _, newTheme in applyAppearance(newTheme) }
            .onChange(of: session.state) { _, newState in
                handleSessionChange(newState)
            }
            .onChange(of: workspaceStore.current?.id) { _, _ in
                // Any pending invite is scoped to the workspace the user was
                // about to join. Switching workspaces means that context is
                // gone — never redeem a stale code into the wrong workspace.
                pendingInviteCode = nil
                pendingInvitePreview = nil
            }
            .onOpenURL { url in handleDeepLink(url) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1060, height: 680)
        .commands {
            CommandGroup(replacing: .appSettings) {}
        }
    }

    @ViewBuilder
    private var rootView: some View {
        switch session.state {
        case .loading:
            SplashView()

        case .signedOut:
            AuthFlowView()
                .environment(session)
                .transition(.opacity)

        case .signedIn:
            if workspaceStore.isLoading {
                SplashView()
            } else if let ws = workspaceStore.current,
                      workspaceStore.hasCompletedOnboarding(for: ws.id) {
                WorkspaceScope(workspace: ws) {
                    ContentView()
                        .environment(session)
                        .environment(workspaceStore)
                }
                .id(ws.id)
                .transition(.opacity)
            } else {
                OnboardingFlowView(
                    initialWorkspace: workspaceStore.current,
                    pendingPreview: pendingInvitePreview,
                    pendingCode: pendingInviteCode
                ) { ws in
                    workspaceStore.select(ws)
                    pendingInvitePreview = nil
                    pendingInviteCode = nil
                }
                .environment(workspaceStore)
                .environment(session)
                .transition(.opacity)
            }
        }
    }

    private var animationKey: Int {
        switch session.state {
        case .loading: return 0
        case .signedOut: return 1
        case .signedIn:
            if workspaceStore.isLoading { return 2 }
            if let ws = workspaceStore.current, workspaceStore.hasCompletedOnboarding(for: ws.id) { return 3 }
            return 4
        }
    }

    private func bootstrap() async {
        // session.bootstrap() flips state, which fires handleSessionChange and
        // triggers workspaceStore.refresh() + deep-link resolution.
        await session.bootstrap()
    }

    // Reacts to sign-in / sign-out after the initial bootstrap (e.g. completing
    // OTP verification, tapping Sign out). Without this, a second-time login
    // leaves workspaceStore empty and the routing drops the user on create/join.
    private func handleSessionChange(_ newState: SessionStore.State) {
        switch newState {
        case .signedIn(let user):
            // Bind before flipping isLoading so the splash render already sees
            // this user's onboarding bucket (not the previous user's).
            workspaceStore.bind(userId: user.id)
            // Flip isLoading synchronously so the router shows the splash
            // instead of flashing the create/join screen for one frame while
            // the refresh Task is scheduled.
            workspaceStore.isLoading = true
            refreshTask?.cancel()
            refreshTask = Task {
                await workspaceStore.refresh()
                if Task.isCancelled { return }
                if let code = pendingInviteCode, pendingInvitePreview == nil {
                    await resolvePreview(code: code)
                }
            }
        case .signedOut:
            refreshTask?.cancel()
            refreshTask = nil
            workspaceStore.reset()
            pendingInviteCode = nil
            pendingInvitePreview = nil
        case .loading:
            break
        }
    }

    // MARK: - Deep link handling

    private func handleDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "kin",
              url.host?.lowercased() == "join",
              let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty
        else { return }

        Task { await resolvePreview(code: code) }
    }

    private func resolvePreview(code: String) async {
        // Can't preview if not signed in — stash the code and wait.
        guard case .signedIn = session.state else {
            pendingInviteCode = code
            return
        }
        do {
            let preview = try await workspaceStore.previewInvite(code: code)
            pendingInviteCode = code
            pendingInvitePreview = preview
        } catch {
            // Invalid or expired code — surface error after navigation settles.
            pendingInviteCode = code
        }
    }

    // MARK: - Appearance / fonts

    private func applyAppearance(_ theme: String) {
        NSApp.appearance = NSAppearance(named: theme == "light" ? .aqua : .darkAqua)
    }

    private func registerInterFont() {
        guard let url = Bundle.main.url(forResource: "InterVariable", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    private func registerFigtreeFont() {
        guard let url = Bundle.main.url(forResource: "Figtree-VariableFont_wght", withExtension: "ttf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
}

// ─── Splash ───────────────────────────────────────────────────────────────────

private struct SplashView: View {
    var body: some View {
        ZStack {
            Kin.bg.ignoresSafeArea()
            Text("cabinet")
                .font(Kin.figtree(36, weight: .black))
                .foregroundStyle(Kin.textPrimary)
        }
    }
}
