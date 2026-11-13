import SwiftUI

/// The signed-in home screen: the Groups this person belongs to.
struct GroupListView: View {
    @Environment(SessionModel.self) private var session
    @Environment(GroupsModel.self) private var model
    let user: SignedInUser

    /// Nil until the first load finishes.
    @State private var groups: [GroupSummary]?
    @State private var loadFailed = false
    @State private var path: [UUID] = []
    @State private var isCreating = false

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            content
                .navigationTitle("群組")
                .navigationDestination(for: UUID.self) { id in
                    GroupDetailView(groupID: id, user: user)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { accountMenu }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("開新群組", systemImage: "plus") { isCreating = true }
                    }
                }
                .refreshable { await reload() }
        }
        .task { await reload() }
        // Coming back from a Group picks up a rename made there.
        .onChange(of: path) { _, new in
            if new.isEmpty { Task { await reload() } }
        }
        .sheet(isPresented: $isCreating) {
            NewGroupView(user: user, onDone: open)
        }
        .sheet(item: $model.pendingInvite) { invite in
            JoinGroupView(invite: invite.token, user: user, onDone: open)
        }
    }

    @ViewBuilder private var content: some View {
        if let groups, !groups.isEmpty {
            List(groups) { group in
                NavigationLink(group.name, value: group.id)
            }
        } else if groups != nil {
            ContentUnavailableView {
                Label("未有群組", systemImage: "person.3")
            } description: {
                Text("開一個群組，或者叫朋友傳條邀請連結畀你。")
            } actions: {
                Button("開新群組") { isCreating = true }
            }
        } else if loadFailed {
            ContentUnavailableView {
                Label("載入唔到群組", systemImage: "wifi.exclamationmark")
            } description: {
                Text("請檢查網絡再試。")
            } actions: {
                Button("再試") { Task { await reload() } }
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

    private func reload() async {
        do {
            groups = try await model.service.myGroups()
            loadFailed = false
        } catch is CancellationError {
        } catch {
            loadFailed = true
        }
    }

    /// Shows a Group the user has just opened or joined.
    private func open(_ id: UUID) {
        Task {
            await reload()
            path = [id]
        }
    }
}
