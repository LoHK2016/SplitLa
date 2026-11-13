import Supabase
import SwiftUI

@main
struct SplitLaApp: App {
    @State private var session: SessionModel

    init() {
        let config = AppConfig.current
        let client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        _session = State(initialValue: SessionModel(auth: SupabaseAuthService(client: client)))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .task { await session.observe() }
        }
    }
}

/// Shows sign-in or the app, depending on whether someone is signed in.
struct RootView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        switch session.state {
        case .loading:
            ProgressView()
        case .signedOut:
            SignInView()
        case .signedIn(let email):
            GroupListView(email: email)
        }
    }
}
