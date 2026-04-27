import SwiftUI

struct OTPEntryView: View {
    @Environment(SessionStore.self) private var session
    @State private var code = ""
    @State private var loading = false
    @State private var resendCooldown = 0
    @FocusState private var focused: Bool

    private let codeLength = 6

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Wordmark
            VStack(spacing: 8) {
                Text("Kin")
                    .font(Kin.inter(48, weight: .bold))
                    .foregroundStyle(Kin.textPrimary)
            }
            .padding(.bottom, 48)

            // Card
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Check your inbox")
                        .font(Kin.inter(15, weight: .semibold))
                        .foregroundStyle(Kin.textPrimary)
                    Text("Enter the 6-digit code we sent to \(session.pendingEmail ?? "your email")")
                        .font(Kin.inter(13))
                        .foregroundStyle(Kin.textSecondary)
                }

                // Code field — styled like a large OTP box
                VStack(alignment: .leading, spacing: 6) {
                    Text("One-time code")
                        .font(Kin.inter(12, weight: .medium))
                        .foregroundStyle(Kin.textSecondary)

                    TextField("123456", text: $code)
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Kin.textPrimary)
                        .multilineTextAlignment(.center)
                        .focused($focused)
                        .onChange(of: code) { _, new in
                            // Strip non-digits and cap at 6 chars
                            let filtered = new.filter(\.isNumber)
                            if filtered != new { code = filtered }
                            if code.count > codeLength { code = String(code.prefix(codeLength)) }
                            if code.count == codeLength { Task { await verify() } }
                        }
                        .onSubmit { Task { await verify() } }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .background(Kin.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(focused ? Kin.accent.opacity(0.5) : Kin.border, lineWidth: 1)
                        )
                }

                if let err = session.authError {
                    Text(err)
                        .font(Kin.inter(12))
                        .foregroundStyle(Kin.statusOffline)
                }

                Button(action: { Task { await verify() } }) {
                    HStack {
                        if loading {
                            ProgressView().scaleEffect(0.7).tint(.white)
                        }
                        Text(loading ? "Verifying…" : "Verify code")
                            .font(Kin.inter(14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(canSubmit ? Kin.accent : Kin.accent.opacity(0.4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit || loading)

                HStack {
                    Button(action: { session.pendingEmail = nil; session.authError = nil }) {
                        Text("← Wrong email?")
                            .font(Kin.inter(12))
                            .foregroundStyle(Kin.textTertiary)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if resendCooldown > 0 {
                        Text("Resend in \(resendCooldown)s")
                            .font(Kin.inter(12))
                            .foregroundStyle(Kin.textQuaternary)
                    } else {
                        Button(action: { Task { await resend() } }) {
                            Text("Resend code")
                                .font(Kin.inter(12))
                                .foregroundStyle(Kin.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(24)
            .background(Kin.surface)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .frame(width: 360)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Kin.bg)
        .onAppear {
            focused = true
            startResendCooldown()
        }
    }

    private var canSubmit: Bool { code.count == codeLength }

    private func verify() async {
        guard canSubmit else { return }
        loading = true
        defer { loading = false }
        do {
            try await session.verifyOTP(code: code)
        } catch {
            session.authError = "Incorrect or expired code. Please try again."
            code = ""
        }
    }

    private func resend() async {
        guard let email = session.pendingEmail else { return }
        session.authError = nil
        do {
            try await session.sendOTP(email: email)
            startResendCooldown()
        } catch {
            session.authError = error.localizedDescription
        }
    }

    private func startResendCooldown() {
        resendCooldown = 60
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            Task { @MainActor in
                resendCooldown -= 1
                if resendCooldown <= 0 { timer.invalidate() }
            }
        }
    }
}
