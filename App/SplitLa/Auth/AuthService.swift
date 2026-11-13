import Foundation
import Supabase

/// Signing in with a code sent by email. The app talks to this, not to Supabase directly.
protocol AuthService: Sendable {
    /// The signed-in user's email whenever it changes; nil when signed out.
    /// The first value arrives as soon as any saved session has been read.
    func sessionChanges() -> AsyncStream<String?>
    func sendCode(to email: String) async throws
    func verify(code: String, for email: String) async throws
    func signOut() async throws
}

struct SupabaseAuthService: AuthService {
    let client: SupabaseClient

    func sessionChanges() -> AsyncStream<String?> {
        AsyncStream { continuation in
            let task = Task {
                for await (_, session) in client.auth.authStateChanges {
                    // A saved session can be past its expiry; it only counts once refreshed.
                    let live = session.flatMap { $0.isExpired ? nil : $0 }
                    continuation.yield(live.map { $0.user.email ?? "" })
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
