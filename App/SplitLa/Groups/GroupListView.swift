import SwiftUI

/// The signed-in home screen: the Groups this person belongs to.
struct GroupListView: View {
    @Environment(SessionModel.self) private var session
    @Environment(GroupsModel.self) private var model
    let user: SignedInUser

    @State private var path: [Route] = []
    @State private var isCreating = false
    @State private var language = AppLanguage.current
    @State private var isShowingLanguageNote = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            content
                .navigationTitle("Groups")
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .group(let id):
                        GroupDetailView(groupID: id, user: user)
                    case .activity(let group, let activity):
                        ActivityView(groupID: group, activityID: activity)
                    case .expense(let group, let expense):
                        ExpenseDetailView(groupID: group, expenseID: expense)
                    case .settlements(let group):
                        SettlementsView(groupID: group)
                    case .personalBudget:
                        PersonalBudgetView()
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { accountMenu }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("New Group", systemImage: "plus") { isCreating = true }
                            .needsConnection()
                    }
                }
                .refreshable { await model.reloadAll() }
        }
        .task { await model.run(for: user) }
        .onChange(of: language) { _, choice in
            choice.makePreferred()
            isShowingLanguageNote = true
        }
        .alert("Language Changed", isPresented: $isShowingLanguageNote) {
            Button("OK") {}
        } message: {
            Text("Close SplitLa and open it again to see it in the new language.")
        }
        .sheet(isPresented: $isCreating) {
            NewGroupView(user: user, onDone: open)
        }
        .sheet(item: $model.pendingInvite) { invite in
            JoinGroupView(invite: invite.token, user: user, onDone: open)
        }
    }

    @ViewBuilder private var content: some View {
        if let groups = model.groups, !groups.isEmpty {
            List {
                Section {
                    ForEach(groups) { group in
                        NavigationLink(group.name, value: Route.group(group.id))
                    }
                }
                Section {
                    NavigationLink(value: Route.personalBudget) {
                        Label("My Personal Budget", systemImage: "lock.shield")
                    }
                } footer: {
                    Text("Your Personal Budget stays on this iPhone. Other Members and SplitLa can’t see it.")
                }
            }
        } else if model.groups != nil {
            ContentUnavailableView {
                Label("No Groups Yet", systemImage: "person.3")
            } description: {
                Text("Start a Group, or ask a friend to send you an invite link.")
            } actions: {
                Button("New Group") { isCreating = true }
                    .needsConnection()
            }
        } else if model.isOffline {
            ContentUnavailableView {
                Label("Couldn’t Load Groups", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await model.reloadAll() } }
            }
        } else {
            ProgressView()
        }
    }

    private var accountMenu: some View {
        Menu {
            Section(user.email) {
                Picker(selection: $language) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(verbatim: option.name).tag(option)
                    }
                } label: {
                    Label("Language", systemImage: "globe")
                }
                .pickerStyle(.menu)
                Button("Sign Out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
        } label: {
            Label("Account", systemImage: "person.crop.circle")
        }
    }

    /// Shows a Group the user has just opened or joined.
    private func open(_ id: UUID) {
        Task {
            await model.reload(id)
            path = [.group(id)]
        }
    }
}

/// The languages SplitLa is written in. The choice applies from the next launch, because
/// iOS reads an app's language once, when it starts.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case cantonese = "zh-HK"

    var id: String { rawValue }

    /// Each language named in itself, so it can be found whatever the app is showing.
    var name: String {
        switch self {
        case .english: "English"
        case .cantonese: "廣東話"
        }
    }

    /// The language the app is showing now.
    static var current: AppLanguage {
        Bundle.main.preferredLocalizations.first.flatMap(AppLanguage.init(rawValue:)) ?? .english
    }

    func makePreferred() {
        UserDefaults.standard.set([rawValue], forKey: "AppleLanguages")
    }
}
