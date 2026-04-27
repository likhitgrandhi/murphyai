import SwiftUI

// Drives workspace setup after sign-in: choose → create/join → preview → seed agents.
// Pass `initialWorkspace` when the user already has a workspace but hasn't finished
// seeding agents — this skips straight to the seeding step.
struct OnboardingFlowView: View {
    @Environment(WorkspaceStore.self) private var workspaceStore
    let onComplete: (KinWorkspace) -> Void

    enum Screen {
        case choice
        case create
        case join
        case joinPreview(InvitePreview, String)   // preview + raw code
        case seed(KinWorkspace)
    }

    @State private var screen: Screen

    init(
        initialWorkspace: KinWorkspace? = nil,
        pendingPreview: InvitePreview? = nil,
        pendingCode: String? = nil,
        onComplete: @escaping (KinWorkspace) -> Void
    ) {
        self.onComplete = onComplete
        if let ws = initialWorkspace {
            _screen = State(initialValue: .seed(ws))
        } else if let preview = pendingPreview, let code = pendingCode {
            _screen = State(initialValue: .joinPreview(preview, code))
        } else if pendingCode != nil {
            // Have code but preview failed — land on join screen with code pre-filled
            _screen = State(initialValue: .join)
        } else {
            _screen = State(initialValue: .choice)
        }
    }

    var body: some View {
        ZStack {
            switch screen {
            case .choice:
                WorkspaceChoiceView { action in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        screen = action == .create ? .create : .join
                    }
                }
                .transition(.trailing)

            case .create:
                WorkspaceCreateView(
                    onCreated: { ws in
                        withAnimation(.easeInOut(duration: 0.2)) { screen = .seed(ws) }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) { screen = .choice }
                    }
                )
                .transition(.trailing)

            case .join:
                WorkspaceJoinView(
                    onPreviewed: { p, code in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            screen = .joinPreview(p, code)
                        }
                    },
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) { screen = .choice }
                    }
                )
                .transition(.trailing)

            case .joinPreview(let preview, let code):
                JoinPreviewView(
                    preview: preview,
                    code: code,
                    onJoined: { ws in
                        withAnimation(.easeInOut(duration: 0.2)) { screen = .seed(ws) }
                    },
                    onCancel: {
                        withAnimation(.easeInOut(duration: 0.2)) { screen = .join }
                    }
                )
                .transition(.trailing)

            case .seed(let ws):
                AgentSeedingView(workspace: ws, onComplete: {
                    workspaceStore.markOnboardingComplete(for: ws.id)
                    onComplete(ws)
                })
                .transition(.trailing)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: screenKey)
    }

    private var screenKey: Int {
        switch screen {
        case .choice:           return 0
        case .create:           return 1
        case .join:             return 2
        case .joinPreview:      return 3
        case .seed:             return 4
        }
    }
}

private extension AnyTransition {
    static var trailing: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal:   .move(edge: .leading).combined(with: .opacity)
        )
    }
    static var leading: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity),
            removal:   .move(edge: .trailing).combined(with: .opacity)
        )
    }
}
