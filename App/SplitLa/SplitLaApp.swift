import SwiftUI

@main
struct SplitLaApp: App {
    @State private var session: SessionModel
    @State private var groups: GroupsModel
    @State private var personalBudget = PersonalBudgetStore()

    init() {
        let services = Services(config: .current)
        _session = State(initialValue: SessionModel(auth: services.auth))
        _groups = State(initialValue: GroupsModel(service: services.groups))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(groups)
                .environment(personalBudget)
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
    @Environment(GroupsModel.self) private var groups
    @Environment(PersonalBudgetStore.self) private var personalBudget

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                SignInView()
            case .signedIn(let user):
                GroupListView(user: user)
                    .id(user.id)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if groups.isOffline { OfflineBanner() }
                    }
            }
        }
        .onChange(of: session.state, initial: true) { _, state in
            if case .signedIn(let user) = state {
                personalBudget.use(owner: user.id)
            } else if state == .signedOut {
                personalBudget.use(owner: nil)
                groups.signedOut()
            }
        }
    }
}
