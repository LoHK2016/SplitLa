import Foundation
import Supabase

/// The person using the app.
struct SignedInUser: Equatable, Sendable {
    let id: UUID
    let email: String

    /// A starting point for the name they go by in a Group.
    var suggestedName: String {
        String(email.prefix { $0 != "@" })
    }
}

/// Signing in with a code sent by email. The app talks to this, not to Supabase directly.
protocol AuthService: Sendable {
    /// The signed-in user whenever it changes; nil when signed out.
    /// The first value arrives as soon as any saved session has been read.
    func sessionChanges() -> AsyncStream<SignedInUser?>
    func sendCode(to email: String) async throws
    func verify(code: String, for email: String) async throws
    func signOut() async throws
}

struct SupabaseAuthService: AuthService {
    let client: SupabaseClient

    func sessionChanges() -> AsyncStream<SignedInUser?> {
        AsyncStream { continuation in
            let task = Task {
                for await (_, session) in client.auth.authStateChanges {
                    // A saved session past its expiry still counts: with no connection it cannot be
                    // refreshed, and the user must still get to their saved data. If the server
                    // later refuses to refresh it, a signed-out event follows.
                    continuation.yield(session.map { SignedInUser(id: $0.user.id, email: $0.user.email ?? "") })
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func sendCode(to email: String) async throws {
        try await client.auth.signInWithOTP(email: email)
    }

    func verify(code: String, for email: String) async throws {
        try await client.auth.verifyOTP(email: email, token: code, type: .email)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
