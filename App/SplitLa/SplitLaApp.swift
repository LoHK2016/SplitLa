import Supabase
import SwiftUI

@main
struct SplitLaApp: App {
    @State private var session: SessionModel
    @State private var groups: GroupsModel

    init() {
        let config = AppConfig.current
        let client = SupabaseClient(supabaseURL: config.supabaseURL, supabaseKey: config.supabaseAnonKey)
        _session = State(initialValue: SessionModel(auth: SupabaseAuthService(client: client)))
        _groups = State(initialValue: GroupsModel(service: GroupsService(client: client)))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(groups)
                // An invite opened while signed out waits here until sign-in.
                .onOpenURL { url in
                    if let invite = InviteLink.invite(from: url) {
                        groups.pendingInvite = PendingInvite(token: invite)
                    }
                }
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
        case .signedIn(let user):
            GroupListView(user: user)
                .id(user.id)
        }
    }
}
