import SwiftUI

struct EmailEntryView: View {
    @Environment(SessionStore.self) private var session
    @State private var email = ""
    @State private var loading = false
    @State private var isSignIn = false
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            // Full-bleed background illustration
            Image("login_bg")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()

            VStack(spacing: 28) {
                // "cabinet" wordmark — Figtree Black 52px
                Text("cabinet")
                    .font(Kin.figtree(52, weight: .black))
                    .foregroundStyle(.white)
                    .tracking(-2.08)

                // Auth card
                VStack(alignment: .leading, spacing: 0) {
                    // ── Header ──────────────────────────────────────────────
                    VStack(spacing: 12) {
                        Text(isSignIn ? "Welcome Back" : "Create Your Account")
                            .font(Kin.figtree(24, weight: .bold))
                            .foregroundStyle(.white)
                            .tracking(-0.144)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .animation(.easeOut(duration: 0.15), value: isSignIn)

                        Text(isSignIn
                             ? "Enter your email and we'll send you a sign-in link."
                             : "Join thousands of creators and start designing with the power of AI in seconds.")
                            .font(Kin.inter(14))
                            .foregroundStyle(Color(hex: "#fafafa")!)
                            .multilineTextAlignment(.center)
                            .tracking(0.21)
                            .frame(maxWidth: .infinity)
                            .animation(.easeOut(duration: 0.15), value: isSignIn)
                    }

                    Spacer().frame(height: 24)

                    // ── Email input ──────────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(Kin.figtree(14, weight: .medium))
                            .foregroundStyle(.white)

                        ZStack(alignment: .leading) {
                            if email.isEmpty {
                                Text("Enter your email")
                                    .font(Kin.figtree(14, weight: .medium))
                                    .foregroundStyle(Color(hex: "#b9bbbe")!)
                                    .padding(.horizontal, 12)
                            }
                            TextField("", text: $email)
                                .textFieldStyle(.plain)
                                .font(Kin.figtree(14, weight: .medium))
                                .foregroundStyle(.white)
                                .focused($focused)
                                .onSubmit { Task { await sendCode() } }
                                .padding(.horizontal, 12)
                        }
                        .frame(height: 44)
                        .background(Color(hex: "#18191C")!)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }

                    Spacer().frame(height: 16)

                    // ── Auth error ───────────────────────────────────────────
                    if let err = session.authError {
                        Text(err)
                            .font(Kin.inter(12))
                            .foregroundStyle(Color(hex: "#FF7B7B") ?? .red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 8)
                    }

                    Spacer().frame(height: session.authError == nil ? 8 : 0)

                    // ── CTA button ───────────────────────────────────────────
                    Button(action: { Task { await sendCode() } }) {
                        HStack(spacing: 8) {
                            if loading {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(loading ? (isSignIn ? "Signing in…" : "Creating…") : (isSignIn ? "Sign in" : "Create account"))
                                .font(Kin.figtree(14, weight: .medium))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(canSubmit ? Color(hex: "#5865f2")! : Color(hex: "#5865f2")!.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSubmit || loading)

                    Spacer().frame(height: 24)

                    // ── Footer ───────────────────────────────────────────────
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) { isSignIn.toggle() }
                        session.authError = nil
                    } label: {
                        Text(isSignIn ? "Don't have an account? Create one" : "Already have an account?")
                            .font(Kin.inter(12))
                            .foregroundStyle(Color(hex: "#fafafa")!)
                            .underline()
                            .tracking(0.18)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(32)
                .background(Color(hex: "#121214")!)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .frame(width: 450)
                .shadow(color: Color.black.opacity(0.1), radius: 32, x: 0, y: 16)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focused = true }
    }

    private var canSubmit: Bool {
        email.contains("@") && email.contains(".")
    }

    private func sendCode() async {
        guard canSubmit else { return }
        loading = true
        defer { loading = false }
        do {
            try await session.sendOTP(email: email.lowercased().trimmingCharacters(in: .whitespaces))
        } catch {
            session.authError = error.localizedDescription
        }
    }
}
