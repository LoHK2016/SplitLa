import Ledger
import SwiftUI

/// One Activity: a summary up top, the Proposals with both halves of their What-if Checks,
/// who is going, and the Expenses.
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
        .alert("Activity Budget", isPresented: $isSettingBudget) {
            TextField("Total for the whole Activity", text: $budgetText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Remove Budget", role: .destructive) { change { try await $0.setBudget(nil, for: activityID) } }
            Button("Save") {
                if let budget = Money(typed: budgetText) {
                    change { try await $0.setBudget(budget, for: activityID) }
                } else {
                    failure = String(localized: "Enter a valid amount.")
                }
            }
        } message: {
            Text("How much the whole Activity is expected to cost. Everyone in the Group can see it.")
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
        let proposals = context.snapshot.proposals.filter { $0.activityId == activityID }
        let chosen = proposals.first { $0.ledger.status == .chosen }
        return List {
            Section {
                ActivityHeader(
                    context: context, activity: activity, isOrganiser: isOrganiser,
                    leftThisMonth: leftThisMonth,
                    editBudget: {
                        budgetText = activity.budgetCents.map { Money(cents: $0).plain } ?? ""
                        isSettingBudget = true
                    })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.accentColor)
            }

            Section {
                ForEach(proposals) { proposal in
                    ProposalRowView(
                        context: context, activity: activity, proposal: proposal, isOrganiser: isOrganiser,
                        personal: personalCheck(
                            for: proposal.proposalID, viewer: model.identity, budget: budgetStore.budget,
                            across: model.allStates, asOf: Date(), calendar: .current),
                        choose: { change { try await $0.choose(proposal.id) } })
                        .listRowBackground(proposal.id == chosen?.id ? Color.accentColor.opacity(0.08) : nil)
                }
                if let chosen {
                    HStack(spacing: 10) {
                        if isOrganiser {
                            Button("Unchoose") { change { try await $0.unchoose(chosen.id) } }
                                .buttonStyle(.bordered)
                        }
                        Button("Turn “\(chosen.title)” into an Expense") { expenseForm = .convert(chosen) }
                            .buttonStyle(.borderedProminent)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .controlSize(.large)
                    .needsConnection()
                }
                Button("New Proposal", systemImage: "plus") { isAddingProposal = true }
                    .needsConnection()
            } header: {
                Text("Proposals")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if budgetStore.budget != nil {
                        Label("Only you can see the “You” amounts.", systemImage: "lock")
                    }
                    if !isOrganiser {
                        Text("Only the Organiser can set the Activity Budget or choose a Proposal.")
                    } else if activity.date == nil {
                        Text("The Activity needs a date before a Proposal can be chosen.")
                    }
                }
            }

            AttendanceSection(context: context, activity: activity) { member, attendance in
                change { try await $0.setAttendance(attendance, of: member, for: activityID) }
            }

            Section("Expenses") {
                ForEach(expenses.reversed()) { expense in
                    NavigationLink(value: Route.expense(group: groupID, expense: expense.id)) {
                        ExpenseRowView(context: context, expense: expense)
                    }
                }
                Button("Record an Expense", systemImage: "plus") { expenseForm = .new }
                    .needsConnection()
            }
        }
        .refreshable { await model.reload(groupID) }
    }

    /// What is left of the viewer's Personal Budget this month. Nil when none is set.
    private var leftThisMonth: Money? {
        guard let budget = budgetStore.budget else { return nil }
        let month = YearMonth(Date(), calendar: .current)
        return committedSpend(for: model.identity, in: month, across: model.allStates, calendar: .current)
            .remaining(of: budget)
    }

    private func change(_ work: @escaping (GroupsService) async throws -> Void) {
        Task {
            do { try await model.change(groupID, work) } catch { failure = failureMessage(error) }
        }
    }
}

/// The coloured block at the top: name, date, who is going, and the three numbers that matter.
private struct ActivityHeader: View {
    let context: GroupContext
    let activity: ActivityRow
    let isOrganiser: Bool
    let leftThisMonth: Money?
    let editBudget: () -> Void

    var body: some View {
        let going = context.state.activity(activity.id.activityID)?.goingMembers.count ?? 0
        let dateText = activity.date?.display ?? String(localized: "No date yet")
        VStack(alignment: .leading, spacing: 14) {
            Text("\(dateText) · \(going) going")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.white.opacity(0.18), in: Capsule())
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.name).font(.largeTitle.bold())
                Text("Organiser: \(context.name(of: activity.organiserId))")
                    .font(.subheadline)
                    .opacity(0.92)
            }
            HStack(spacing: 8) {
                if isOrganiser {
                    Button(action: editBudget) {
                        Tile(title: "Activity Budget", value: budgetText, hint: "Tap to change")
                    }
                    .buttonStyle(.plain)
                    .needsConnection()
                } else {
                    Tile(title: "Activity Budget", value: budgetText, hint: nil)
                }
                Tile(title: "Spent", value: context.state.spent(in: activity.id.activityID).description, hint: nil)
                if let leftThisMonth {
                    Tile(
                        title: leftThisMonth < .zero ? "You’re over by" : "You have left",
                        value: (leftThisMonth < .zero ? -leftThisMonth : leftThisMonth).description,
                        hint: "this month")
                }
            }
            // Every tile as tall as the tallest, so a wrapped title does not make them uneven.
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var budgetText: String {
        activity.budgetCents.map { Money(cents: $0).description } ?? String(localized: "Not set")
    }
}

/// One small figure in the header.
private struct Tile: View {
    let title: LocalizedStringKey
    let value: String
    let hint: LocalizedStringKey?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).opacity(0.92)
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let hint { Text(hint).font(.caption2).opacity(0.85) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 14))
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
        Section("Attendance · \(going) going") {
            ForEach(context.snapshot.members) { member in
                let attendance = state?.attendance(of: member.id.memberID) ?? .noReply
                HStack {
                    Text(member.name)
                    if member.id == context.me?.id { Tag("You", tint: .blue) }
                    if member.userID == nil { Tag("Placeholder") }
                    Spacer()
                    if member.id == context.me?.id || member.userID == nil {
                        Picker("Attendance", selection: Binding(get: { attendance }, set: { set(member.id, $0) })) {
                            ForEach([Attendance.going, .notGoing, .noReply], id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .labelsHidden()
                        .needsConnection()
                    } else {
                        Text(attendance.label).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

extension Attendance {
    var label: LocalizedStringKey {
        switch self {
        case .going: "Going"
        case .notGoing: "Not going"
        case .noReply: "No reply"
        }
    }
}

/// One Proposal, compact: my Share in a tile, then what it costs and both halves of the
/// What-if Check as small labels.
private struct ProposalRowView: View {
    let context: GroupContext
    let activity: ActivityRow
    let proposal: ProposalRow
    let isOrganiser: Bool
    /// The private half of the check. Nil when there is no Personal Budget.
    let personal: PersonalCheck?
    let choose: () -> Void

    var body: some View {
        let state = context.state
        let me = context.me?.id.memberID
        let amIGoing = me.flatMap { state.activity(activity.id.activityID)?.attendance(of: $0) } == .going
        let status = proposal.ledger.status
        let share = me.flatMap { state.share(of: proposal.proposalID, for: $0) }
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 2) {
                Text(status == .converted ? "–" : share?.description ?? "–")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(status == .chosen ? Color.accentColor : .primary)
                Text(amIGoing ? "Your share" : "If you go").font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 76, height: 72)
            .background(
                status == .chosen ? Color.accentColor.opacity(0.14) : Color(.tertiarySystemFill),
                in: RoundedRectangle(cornerRadius: 16))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(proposal.title).font(.headline)
                    if status == .chosen {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Chosen")
                    }
                }
                Text(amountLine(total: state.total(of: proposal.proposalID)))
                    .font(.subheadline).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) {
                    if status == .converted {
                        Pill("Turned into an Expense", style: .neutral)
                    } else {
                        if let check = state.activityCheck(for: proposal.proposalID) {
                            if check.isOver {
                                Pill("Over budget by \((-check.remaining).description)", style: .warning)
                            } else {
                                Pill("Within budget · \(check.remaining.description) left", style: .good)
                            }
                        }
                        if let personal {
                            if personal.isOver {
                                Pill("You: over by \((-personal.remaining).description)", style: .warning, systemImage: "lock")
                            } else {
                                Pill("You: \(personal.remaining.description) left", style: .neutral, systemImage: "lock")
                            }
                        }
                    }
                }
                if isOrganiser && status == .open && activity.date != nil {
                    Button("Choose", action: choose)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .needsConnection()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func amountLine(total: Money?) -> LocalizedStringKey {
        switch proposal.ledger.amount {
        case .perPerson(let each):
            if let total { return "\(each.description) per person · \(total.description) in total" }
            return "\(each.description) per person"
        case .total(let amount):
            return "\(amount.description) in total"
        }
    }
}

/// A small coloured label for one result of a What-if Check.
private struct Pill: View {
    enum Style { case good, warning, neutral }

    let text: LocalizedStringKey
    let style: Style
    let systemImage: String?

    init(_ text: LocalizedStringKey, style: Style, systemImage: String? = nil) {
        self.text = text
        self.style = style
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch style {
        case .warning: .white
        case .good: Color(red: 0.08, green: 0.37, blue: 0.23)
        case .neutral: .primary
        }
    }

    private var background: Color {
        switch style {
        case .warning: Color(red: 0.71, green: 0.14, blue: 0.09)
        case .good: Color(red: 0.87, green: 0.95, blue: 0.90)
        case .neutral: Color(.tertiarySystemFill)
        }
    }
}

/// Lays children out left to right, wrapping onto new lines when they run out of room.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if needed > width && !row.indices.isEmpty {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
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
                Text("Paid by \(context.name(of: expense.paidBy)) · \(expense.date.display)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if expense.isDeleted {
                Tag("Deleted", tint: .red)
            } else {
                Text((expense.ledger?.total ?? Money(cents: expense.amountCents)).description)
                    .monospacedDigit()
            }
        }
    }
}
