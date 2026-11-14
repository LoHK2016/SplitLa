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
                    Button("Rename Group", systemImage: "pencil") {
                        newName = model.context(groupID)?.snapshot.group.name ?? ""
                        isRenaming = true
                    }
                    Button("Add Placeholder Member", systemImage: "person.badge.plus") {
                        placeholderName = ""
                        isAddingPlaceholder = true
                    }
                    Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        isConfirmingLeave = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .needsConnection()
            }
        }
        .alert("Rename Group", isPresented: $isRenaming) {
            TextField("Group name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { change { try await $0.rename(groupID, to: newName.trimmed) } }
                .disabled(newName.trimmed.isEmpty)
        }
        .alert("Add Placeholder Member", isPresented: $isAddingPlaceholder) {
            TextField("Their name", text: $placeholderName)
            Button("Cancel", role: .cancel) {}
            Button("Add") { change { try await $0.addPlaceholder(named: placeholderName.trimmed, to: groupID) } }
                .disabled(placeholderName.trimmed.isEmpty)
        } message: {
            Text("For friends who don’t use the app. They can claim it when they join with the invite link.")
        }
        .confirmationDialog("Leave this Group?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive, action: leave)
        } message: {
            Text("Your accounts stay, and other Members still see your Balance. You can come back with the invite link and claim it again.")
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
            Section("Balances") {
                ForEach(context.snapshot.members) { member in
                    HStack {
                        Text(member.name)
                        if member.id == context.me?.id { Tag("You", tint: .blue) }
                        if member.userID == nil { Tag("Placeholder") }
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
                                Text("\(context.name(of: transfer.from)) pays \(context.name(of: transfer.to))")
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
                    Text("Settle Up")
                } footer: {
                    Text("Make these payments and everyone is square. SplitLa doesn’t move money: once you’ve paid by FPS or PayMe, tap to record it.")
                }
            }

            Section {
                NavigationLink(value: Route.settlements(group: groupID)) {
                    LabeledContent("Settlements", value: String(localized: "\(context.snapshot.settlements.filter { !$0.isDeleted }.count) recorded"))
                }
            }

            Section("Activities") {
                ForEach(context.snapshot.activities.reversed()) { activity in
                    NavigationLink(value: Route.activity(group: groupID, activity: activity.id)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.name)
                            Text(activity.date?.display ?? String(localized: "No date yet"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Button("New Activity", systemImage: "plus") { isAddingActivity = true }
                    .needsConnection()
            }

            Section {
                ShareLink(
                    item: InviteLink.url(for: context.snapshot.group.inviteToken),
                    subject: Text("Join “\(context.snapshot.group.name)”"),
                    message: Text("I started “\(context.snapshot.group.name)” on SplitLa. Tap the link to join and split costs together.")
                ) {
                    Label("Invite Friends", systemImage: "square.and.arrow.up")
                }
            } footer: {
                Text("Anyone with the link can join this Group.")
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
