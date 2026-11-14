import Ledger
import SwiftUI

/// One Group: everyone's Balance, how to settle up, its Activities, and its Members.
/// Other Members' changes show up as they happen.
struct GroupDetailView: View {
    @Environment(GroupsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    let user: SignedInUser

    @State private var isRenaming = false
    @State private var newName = ""
    @State private var isAddingPlaceholder = false
    @State private var placeholderName = ""
    @State private var isAddingActivity = false
    @State private var isConfirmingLeave = false
    @State private var settlementDraft: SettlementDraft?
    @State private var failure: String?

    var body: some View {
        Group {
            if let context = model.context(groupID) {
                list(context)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model.context(groupID)?.snapshot.group.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("改群組名", systemImage: "pencil") {
                        newName = model.context(groupID)?.snapshot.group.name ?? ""
                        isRenaming = true
                    }
                    Button("加佔位成員", systemImage: "person.badge.plus") {
                        placeholderName = ""
                        isAddingPlaceholder = true
                    }
                    Button("退出群組", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        isConfirmingLeave = true
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
                .needsConnection()
            }
        }
        .alert("改群組名", isPresented: $isRenaming) {
            TextField("群組名", text: $newName)
            Button("取消", role: .cancel) {}
            Button("儲存") { change { try await $0.rename(groupID, to: newName.trimmed) } }
                .disabled(newName.trimmed.isEmpty)
        }
        .alert("加佔位成員", isPresented: $isAddingPlaceholder) {
            TextField("佢個名", text: $placeholderName)
            Button("取消", role: .cancel) {}
            Button("加入") { change { try await $0.addPlaceholder(named: placeholderName.trimmed, to: groupID) } }
                .disabled(placeholderName.trimmed.isEmpty)
        } message: {
            Text("畀未裝 App 嘅朋友用。佢之後經邀請連結加入嗰陣可以認領返。")
        }
        .confirmationDialog("退出呢個群組？", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("退出群組", role: .destructive, action: leave)
        } message: {
            Text("你條數會留低，其他成員仍然見到你嘅結餘。你之後可以經邀請連結返嚟認領返。")
        }
        .sheet(isPresented: $isAddingActivity) {
            NewActivityView(groupID: groupID)
        }
        .sheet(item: $settlementDraft) { draft in
            SettlementFormView(groupID: groupID, draft: draft)
        }
        .failureAlert($failure)
        .task { await model.reload(groupID) }
        .onChange(of: model.context(groupID) == nil && model.groups != nil) { _, gone in
            // No longer a Member, so there is nothing here to show.
            if gone { dismiss() }
        }
    }

    private func list(_ context: GroupContext) -> some View {
        let balances = context.state.balances()
        let transfers = context.state.suggestedTransfers()
        return List {
            Section("結餘") {
                ForEach(context.snapshot.members) { member in
                    HStack {
                        Text(member.name)
                        if member.id == context.me?.id { Tag("你", tint: .blue) }
                        if member.userID == nil { Tag("佔位") }
                        Spacer()
                        BalanceText(balance: balances[member.id.memberID] ?? .zero)
                    }
                }
            }

            if !transfers.isEmpty {
                Section {
                    ForEach(Array(transfers.enumerated()), id: \.offset) { _, transfer in
                        Button {
                            if let from = transfer.from.uuid, let to = transfer.to.uuid {
                                settlementDraft = SettlementDraft(from: from, to: to, amount: transfer.amount)
                            }
                        } label: {
                            HStack {
                                Text("\(context.name(of: transfer.from)) 畀 \(context.name(of: transfer.to))")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text(transfer.amount.description).foregroundStyle(.primary)
                                Image(systemName: "checkmark.circle").foregroundStyle(.tint)
                            }
                        }
                        .tint(.primary)
                        .needsConnection()
                    }
                } header: {
                    Text("建議轉帳")
                } footer: {
                    Text("照住過數就找清晒。SplitLa 唔會幫你過數；用 FPS 或 PayMe 畀咗錢之後，撳一下記低。")
                }
            }

            Section {
                NavigationLink(value: Route.settlements(group: groupID)) {
                    LabeledContent("找數記錄", value: "\(context.snapshot.settlements.filter { !$0.isDeleted }.count) 筆")
                }
            }

            Section("活動") {
                ForEach(context.snapshot.activities.reversed()) { activity in
                    NavigationLink(value: Route.activity(group: groupID, activity: activity.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name)
                            Text(activity.date?.display ?? "未定日期")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("開新活動", systemImage: "plus") { isAddingActivity = true }
                    .needsConnection()
            }

            Section {
                ShareLink(
                    item: InviteLink.url(for: context.snapshot.group.inviteToken),
                    subject: Text("加入「\(context.snapshot.group.name)」"),
                    message: Text("我喺 SplitLa 開咗「\(context.snapshot.group.name)」，撳條連結加入一齊夾數。")
                ) {
                    Label("邀請朋友", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("收到連結嘅人撳一下就可以加入呢個群組。")
            }
        }
        .refreshable { await model.reload(groupID) }
    }

    private func change(_ work: @escaping (GroupsService) async throws -> Void) {
        Task {
            do { try await model.change(groupID, work) } catch { failure = failureMessage(error) }
        }
    }

    private func leave() {
        Task {
            do {
                try await model.change(groupID) { try await $0.leave(groupID) }
                dismiss()
            } catch {
                failure = failureMessage(error)
            }
        }
    }
}
