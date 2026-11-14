import Ledger
import SwiftUI

/// One Activity: who is going, the Proposals with their What-if Checks, and the Expenses.
struct ActivityView: View {
    @Environment(GroupsModel.self) private var model
    @Environment(PersonalBudgetStore.self) private var budgetStore
    let groupID: UUID
    let activityID: UUID

    @State private var isSettingBudget = false
    @State private var budgetText = ""
    @State private var isAddingProposal = false
    @State private var expenseForm: ExpenseFormView.Mode?
    @State private var failure: String?

    var body: some View {
        Group {
            if let context = model.context(groupID), let activity = context.activity(activityID) {
                list(context, activity)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model.context(groupID)?.activity(activityID)?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .alert("活動預算", isPresented: $isSettingBudget) {
            TextField("成個活動總共幾多錢", text: $budgetText).keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("移除預算", role: .destructive) { change { try await $0.setBudget(nil, for: activityID) } }
            Button("儲存") {
                if let budget = Money(typed: budgetText) {
                    change { try await $0.setBudget(budget, for: activityID) }
                } else {
                    failure = "請入一個有效嘅金額。"
                }
            }
        } message: {
            Text("成個活動預計總共洗幾多，全組都睇到。")
        }
        .sheet(isPresented: $isAddingProposal) {
            ProposalFormView(groupID: groupID, activityID: activityID)
        }
        .sheet(item: $expenseForm) { mode in
            ExpenseFormView(groupID: groupID, activityID: activityID, mode: mode)
        }
        .failureAlert($failure)
    }

    private func list(_ context: GroupContext, _ activity: ActivityRow) -> some View {
        let isOrganiser = context.me?.id == activity.organiserId
        let expenses = context.snapshot.expenses.filter { $0.activityId == activityID }
        let spent = context.state.spent(in: activityID.activityID)
        let proposals = context.snapshot.proposals.filter { $0.activityId == activityID }
        return List {
            Section {
                LabeledContent("日期", value: activity.date?.display ?? "未定")
                LabeledContent("主辦人", value: context.name(of: activity.organiserId))
                LabeledContent("已有開支", value: spent.description)
                HStack {
                    LabeledContent("活動預算", value: activity.budgetCents.map { Money(cents: $0).description } ?? "未定")
                    if isOrganiser {
                        Button("設定") {
                            budgetText = activity.budgetCents.map { Money(cents: $0).plain } ?? ""
                            isSettingBudget = true
                        }
                        .buttonStyle(.borderless)
                        .needsConnection()
                    }
                }
            } footer: {
                if !isOrganiser { Text("只有主辦人可以定活動預算同選定提案。") }
            }

            AttendanceSection(context: context, activity: activity) { member, attendance in
                change { try await $0.setAttendance(attendance, of: member, for: activityID) }
            }

            Section("提案") {
                ForEach(proposals) { proposal in
                    ProposalRowView(
                        context: context, activity: activity, proposal: proposal, isOrganiser: isOrganiser,
                        personal: personalCheck(
                            for: proposal.proposalID, viewer: model.identity, budget: budgetStore.budget,
                            across: model.allStates, asOf: Date(), calendar: .current),
                        choose: { change { try await $0.choose(proposal.id) } },
                        unchoose: { change { try await $0.unchoose(proposal.id) } },
                        convert: { expenseForm = .convert(proposal) })
                }
                Button("開新提案", systemImage: "plus") { isAddingProposal = true }
                    .needsConnection()
            }

            Section("開支") {
                ForEach(expenses.reversed()) { expense in
                    NavigationLink(value: Route.expense(group: groupID, expense: expense.id)) {
                        ExpenseRowView(context: context, expense: expense)
                    }
                }
                Button("記一筆開支", systemImage: "plus") { expenseForm = .new }
                    .needsConnection()
            }
        }
        .refreshable { await model.reload(groupID) }
    }

    private func change(_ work: @escaping (GroupsService) async throws -> Void) {
        Task {
            do { try await model.change(groupID, work) } catch { failure = failureMessage(error) }
        }
    }
}

/// Who is going. A Member answers for themselves, or for a Placeholder Member.
private struct AttendanceSection: View {
    let context: GroupContext
    let activity: ActivityRow
    let set: (UUID, Attendance) -> Void

    var body: some View {
        let state = context.state.activity(activity.id.activityID)
        let going = state?.goingMembers.count ?? 0
        Section("出席（\(going) 人去）") {
            ForEach(context.snapshot.members) { member in
                let attendance = state?.attendance(of: member.id.memberID) ?? .noReply
                HStack {
                    Text(member.name)
                    if member.id == context.me?.id { Tag("你", tint: .blue) }
                    if member.userID == nil { Tag("佔位") }
                    Spacer()
                    if member.id == context.me?.id || member.userID == nil {
                        Picker("出席狀態", selection: Binding(get: { attendance }, set: { set(member.id, $0) })) {
                            Text("去").tag(Attendance.going)
                            Text("唔去").tag(Attendance.notGoing)
                            Text("未覆").tag(Attendance.noReply)
                        }
                        .labelsHidden()
                        .needsConnection()
                    } else {
                        Text(label(attendance)).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func label(_ attendance: Attendance) -> String {
        switch attendance {
        case .going: "去"
        case .notGoing: "唔去"
        case .noReply: "未覆"
        }
    }
}

/// One Proposal: what it costs, my Share, and both halves of the What-if Check.
private struct ProposalRowView: View {
    let context: GroupContext
    let activity: ActivityRow
    let proposal: ProposalRow
    let isOrganiser: Bool
    /// The private half of the check. Nil when there is no Personal Budget.
    let personal: PersonalCheck?
    let choose: () -> Void
    let unchoose: () -> Void
    let convert: () -> Void

    var body: some View {
        let state = context.state
        let me = context.me?.id.memberID
        let amIGoing = me.flatMap { state.activity(activity.id.activityID)?.attendance(of: $0) } == .going
        let status = proposal.ledger.status
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(proposal.title).font(.headline)
                if status == .chosen { Tag("選定", tint: .green) }
                if status == .converted { Tag("已轉做開支") }
            }
            Text(amountLine(total: state.total(of: proposal.proposalID)))
                .font(.subheadline).foregroundStyle(.secondary)

            if status != .converted {
                if let me, let share = state.share(of: proposal.proposalID, for: me) {
                    Text("你嘅份額：\(share.description)\(amIGoing ? "" : "（假設你去）")")
                        .font(.subheadline)
                }
                if let check = state.activityCheck(for: proposal.proposalID) {
                    Label(
                        check.isOver ? "超出活動預算 \((-check.remaining).description)" : "活動預算內，仲剩 \(check.remaining.description)",
                        systemImage: check.isOver ? "exclamationmark.triangle.fill" : "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(check.isOver ? .orange : .green)
                }
                if let personal {
                    Label(
                        personal.isOver
                            ? "會超出你嘅個人預算 \((-personal.remaining).description)"
                            : "去呢度，你今個月仲剩 \(personal.remaining.description)",
                        systemImage: personal.isOver ? "exclamationmark.octagon.fill" : "lock.shield")
                        .font(.subheadline.weight(personal.isOver ? .semibold : .regular))
                        .foregroundStyle(personal.isOver ? .red : .secondary)
                }
                HStack {
                    if isOrganiser && status == .open {
                        Button("選定", action: choose).disabled(activity.date == nil)
                    }
                    if isOrganiser && status == .chosen {
                        Button("取消選定", action: unchoose)
                    }
                    if status == .chosen {
                        Button("轉做開支", action: convert)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .needsConnection()
                if isOrganiser && status == .open && activity.date == nil {
                    Text("活動要有日期先可以選定提案。").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func amountLine(total: Money?) -> String {
        switch proposal.ledger.amount {
        case .perPerson(let each):
            return "每人 \(each.description)" + (total.map { "，而家總共 \($0.description)" } ?? "")
        case .total(let amount):
            return "總數 \(amount.description)"
        }
    }
}

/// One line for an Expense in a list.
struct ExpenseRowView: View {
    let context: GroupContext
    let expense: ExpenseRow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).strikethrough(expense.isDeleted)
                Text("\(context.name(of: expense.paidBy)) 畀錢 · \(expense.date.display)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if expense.isDeleted {
                Tag("已刪除", tint: .red)
            } else {
                Text((expense.ledger?.total ?? Money(cents: expense.amountCents)).description)
            }
        }
    }
}
