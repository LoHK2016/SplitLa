import Observation

/// Who is signed in, for the whole app.
@MainActor @Observable
final class SessionModel {
    enum State: Equatable {
        /// The saved session has not been read yet.
        case loading
        case signedOut
        case signedIn(email: String)
    }

    private(set) var state: State = .loading
    private let auth: any AuthService

    init(auth: any AuthService) {
        self.auth = auth
    }

    /// Follows sign-in and sign-out for as long as the app runs.
    func observe() async {
        for await email in auth.sessionChanges() {
            state = email.map { .signedIn(email: $0) } ?? .signedOut
        }
    }

    func sendCode(to email: String) async throws {
        try await auth.sendCode(to: email)
    }

    func verify(code: String, for email: String) async throws {
        try await auth.verify(code: code, for: email)
    }

    func signOut() async {
        try? await auth.signOut()
    }
}
