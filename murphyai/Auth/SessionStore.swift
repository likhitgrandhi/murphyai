import Foundation
import Observation
import Supabase

// ─── User model ───────────────────────────────────────────────────────────────

struct KinUser: Equatable, Sendable {
    let id: UUID
    let email: String
    var displayName: String?
    var avatarURL: URL?

    var initials: String {
        let name = displayName ?? email
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// ─── SessionStore ─────────────────────────────────────────────────────────────

@Observable
@MainActor
final class SessionStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(KinUser)
    }

    var state: State = .loading
    var authError: String?

    // Tracks which step of the two-step OTP flow we're on
    var pendingEmail: String?

    // MARK: - Lifecycle

    func bootstrap() async {
        // authStateChanges emits the cached local session as its first event —
        // no network round-trip required, so session survives app rebuilds.
        for await (_, session) in kinSupabase.auth.authStateChanges {
            if let session {
                state = .signedIn(KinUser(from: session.user))
            } else {
                state = .signedOut
            }
            return
        }
        state = .signedOut
    }

    // MARK: - Auth actions

    func sendOTP(email: String) async throws {
        authError = nil
        try await kinSupabase.auth.signInWithOTP(
            email: email,
            shouldCreateUser: true
        )
        pendingEmail = email
    }

    func verifyOTP(code: String) async throws {
        guard let email = pendingEmail else { return }
        authError = nil
        let response = try await kinSupabase.auth.verifyOTP(
            email: email,
            token: code,
            type: .email
        )
        switch response {
        case .session(let session):
            state = .signedIn(KinUser(from: session.user))
        case .user(let user):
            state = .signedIn(KinUser(from: user))
        }
    }

    func signOut() async {
        try? await kinSupabase.auth.signOut()
        pendingEmail = nil
        authError = nil
        state = .signedOut
    }

    var currentUser: KinUser? {
        guard case .signedIn(let user) = state else { return nil }
        return user
    }
}

// ─── Supabase → KinUser mapping ───────────────────────────────────────────────

private extension KinUser {
    init(from user: Supabase.User) {
        id = user.id
        email = user.email ?? ""
        // Decode via JSON to avoid depending on AnyJSON's internal representation
        if let data = try? JSONEncoder().encode(user.userMetadata),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            displayName = json["display_name"] as? String
            avatarURL = (json["avatar_url"] as? String).flatMap { URL(string: $0) }
        }
    }
}
