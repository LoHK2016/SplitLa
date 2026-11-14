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
        let me = context.me?.id.memberID
        let mine = transfers.first { $0.from == me || $0.to == me }
        let others = transfers.filter { $0.from != me && $0.to != me }
        return List {
            if let me {
                Section {
                    BalanceCard(
                        context: context, balance: balances[me] ?? .zero, me: me, transfer: mine,
                        record: { record($0) })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.accentColor)
                }
            }

            Section("Members") {
                ForEach(context.snapshot.members) { member in
                    HStack(spacing: 12) {
                        Avatar(member: member)
                        Text(member.name)
                        if member.id == context.me?.id { Tag("You", tint: .blue) }
                        if member.userID == nil { Tag("Placeholder") }
                        Spacer()
                        BalanceText(balance: balances[member.id.memberID] ?? .zero)
                            .monospacedDigit()
                    }
                }
            }

            if !others.isEmpty {
                Section {
                    ForEach(Array(others.enumerated()), id: \.offset) { _, transfer in
                        Button { record(transfer) } label: {
                            HStack {
                                Text("\(context.name(of: transfer.from)) pays \(context.name(of: transfer.to))")
                                Spacer()
                                Text(transfer.amount.description).monospacedDigit()
                                Image(systemName: "checkmark.circle").foregroundStyle(Color.accentColor)
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
                ForEach(context.snapshot.activities.reversed()) { activity in
                    NavigationLink(value: Route.activity(group: groupID, activity: activity.id)) {
                        ActivityRowView(context: context, activity: activity)
                    }
                }
                Button("New Activity", systemImage: "plus") { isAddingActivity = true }
                    .needsConnection()
            } header: {
                Text("Activities")
            }

            Section {
                NavigationLink(value: Route.settlements(group: groupID)) {
                    LabeledContent("Settlements", value: String(localized: "\(context.snapshot.settlements.filter { !$0.isDeleted }.count) recorded"))
                }
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

    /// Opens the Settlement form filled in from a suggested transfer.
    private func record(_ transfer: Transfer) {
        if let from = transfer.from.uuid, let to = transfer.to.uuid {
            settlementDraft = SettlementDraft(from: from, to: to, amount: transfer.amount)
        }
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

/// The coloured card at the top: my Balance in large type, and the one payment that settles it.
private struct BalanceCard: View {
    let context: GroupContext
    let balance: Money
    let me: MemberID
    /// The suggested transfer that involves me, if any.
    let transfer: Transfer?
    let record: (Transfer) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Balance in This Group").font(.subheadline).opacity(0.92)
                headline
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let transfer {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        let other = transfer.from == me ? transfer.to : transfer.from
                        if let member = context.snapshot.members.first(where: { $0.id.memberID == other }) {
                            Avatar(member: member, size: 30)
                        }
                        Group {
                            if transfer.from == me {
                                Text("You pay \(context.name(of: transfer.to)) \(transfer.amount.description)")
                            } else {
                                Text("\(context.name(of: transfer.from)) owes you \(transfer.amount.description)")
                            }
                        }
                        .font(.subheadline.weight(.medium))
                    }
                    Button { record(transfer) } label: {
                        Text(transfer.from == me ? "Record as Paid" : "Record as Received")
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(Color.accentColor)
                            .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .needsConnection()
                }
                .padding(10)
                .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var headline: some View {
        if balance > .zero {
            Text("You get back \(balance.description)")
        } else if balance < .zero {
            Text("You owe \((-balance).description)")
        } else {
            Text("You’re all square")
        }
    }
}

/// One Activity in the list: a date badge, its name, where it stands, and who is going.
private struct ActivityRowView: View {
    let context: GroupContext
    let activity: ActivityRow

    var body: some View {
        let going = context.state.activity(activity.id.activityID)?.goingMembers ?? []
        HStack(spacing: 14) {
            DateBadge(day: activity.date)
            VStack(alignment: .leading, spacing: 4) {
                Text(activity.name).font(.headline)
                if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                if !going.isEmpty {
                    HStack(spacing: 6) {
                        HStack(spacing: -6) {
                            ForEach(going.prefix(5), id: \.self) { id in
                                if let member = context.snapshot.members.first(where: { $0.id.memberID == id }) {
                                    Avatar(member: member, size: 22)
                                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 1.5))
                                }
                            }
                        }
                        Text("\(going.count) going").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Which Proposal was chosen, and whether it has become an Expense.
    private var status: String? {
        let proposals = context.snapshot.proposals.filter { $0.activityId == activity.id }
        if let chosen = proposals.first(where: { $0.ledger.status == .chosen }) {
            return String(localized: "Chosen: \(chosen.title)")
        }
        if let converted = proposals.last(where: { $0.ledger.status == .converted }) {
            return String(localized: "\(converted.title) · turned into an Expense")
        }
        if !proposals.isEmpty { return String(localized: "\(proposals.count) Proposals") }
        return nil
    }
}

/// The month and day of an Activity, like a page torn from a calendar.
private struct DateBadge: View {
    let day: Day?

    var body: some View {
        VStack(spacing: 0) {
            if let day {
                Text(day.date(), format: .dateTime.month(.abbreviated))
                    .font(.caption2.weight(.semibold))
                // Just the number: some languages add a suffix (14日) that crowds the badge.
                Text(verbatim: String(day.day))
                    .font(.system(.title2, design: .rounded).weight(.heavy))
            } else {
                Image(systemName: "calendar.badge.questionmark").font(.title3)
            }
        }
        .foregroundStyle(Color.accentColor)
        .frame(width: 50, height: 54)
        .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}
