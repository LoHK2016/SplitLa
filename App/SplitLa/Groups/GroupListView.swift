import SwiftUI

/// The signed-in home screen: the Groups this person belongs to.
struct GroupListView: View {
    @Environment(SessionModel.self) private var session
    @Environment(GroupsModel.self) private var model
    let user: SignedInUser

    @State private var path: [Route] = []
    @State private var isCreating = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            content
                .navigationTitle("群組")
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
                        Button("開新群組", systemImage: "plus") { isCreating = true }
                            .needsConnection()
                    }
                }
                .refreshable { await model.reloadAll() }
        }
        .task { await model.run(for: user) }
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
                        Label("我嘅個人預算", systemImage: "lock.shield")
                    }
                } footer: {
                    Text("個人預算只儲喺呢部機，其他成員同 SplitLa 都睇唔到。")
                }
            }
        } else if model.groups != nil {
            ContentUnavailableView {
                Label("未有群組", systemImage: "person.3")
            } description: {
                Text("開一個群組，或者叫朋友傳條邀請連結畀你。")
            } actions: {
                Button("開新群組") { isCreating = true }
                    .needsConnection()
            }
        } else if model.isOffline {
            ContentUnavailableView {
                Label("載入唔到群組", systemImage: "wifi.exclamationmark")
            } description: {
                Text("請檢查網絡再試。")
            } actions: {
                Button("再試") { Task { await model.reloadAll() } }
            }
        } else {
            ProgressView()
        }
    }

    private var accountMenu: some View {
        Menu {
            Section(user.email) {
                Button("登出", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    Task { await session.signOut() }
                }
            }
        } label: {
            Label("帳戶", systemImage: "person.crop.circle")
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
