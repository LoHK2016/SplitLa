import SwiftUI

/// One Group: who is in it, and the invite link to bring in more Members.
/// Stays current while open: renames and new Members show up as they happen.
struct GroupDetailView: View {
    @Environment(GroupsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    let user: SignedInUser

    @State private var group: GroupSummary?
    @State private var members: [GroupMember] = []
    @State private var loadFailed = false
    @State private var isRenaming = false
    @State private var newName = ""
    @State private var renameFailed = false

    var body: some View {
        content
            .navigationTitle(group?.name ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if let group {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("改名", systemImage: "pencil") {
                            newName = group.name
                            isRenaming = true
                        }
                    }
                }
            }
            .alert("改群組名", isPresented: $isRenaming) {
                TextField("群組名", text: $newName)
                Button("取消", role: .cancel) {}
                Button("儲存", action: rename)
                    .disabled(newName.trimmed.isEmpty)
            }
            .alert("改唔到名", isPresented: $renameFailed) {
                Button("好") {}
            } message: {
                Text("請檢查網絡再試。")
            }
            .task {
                await reload()
                for await _ in model.service.changes(in: groupID) {
                    await reload()
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let group {
            List {
                Section("成員（\(members.count)）") {
                    ForEach(members) { member in
                        LabeledContent(member.name) {
                            if member.userID == user.id { Text("你") }
                        }
                    }
                }
                Section {
                    ShareLink(
                        item: InviteLink.url(for: group.inviteToken),
                        subject: Text("加入「\(group.name)」"),
                        message: Text("我喺 SplitLa 開咗「\(group.name)」，撳條連結加入一齊夾數。")
                    ) {
                        Label("邀請朋友", systemImage: "person.badge.plus")
                    }
                } footer: {
                    Text("收到連結嘅人撳一下就可以加入呢個群組。")
                }
            }
            .refreshable { await reload() }
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

    private func reload() async {
        do {
            async let latestGroup = model.service.group(groupID)
            async let latestMembers = model.service.members(of: groupID)
            guard let found = try await latestGroup else {
                // No longer a Member, so there is nothing here to show.
                dismiss()
                return
            }
            (group, members) = (found, try await latestMembers)
            loadFailed = false
        } catch is CancellationError {
        } catch {
            loadFailed = group == nil
        }
    }

    private func rename() {
        let name = newName.trimmed
        guard !name.isEmpty, name != group?.name else { return }
        Task {
            do {
                try await model.service.rename(groupID, to: name)
                await reload()
            } catch {
                renameFailed = true
            }
        }
    }
}
