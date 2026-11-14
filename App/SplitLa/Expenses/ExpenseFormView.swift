import Ledger
import SwiftUI

/// Sheet for recording an Expense, changing one, or turning a Chosen Proposal into one.
struct ExpenseFormView: View {
    enum Mode: Identifiable {
        case new
        case edit(ExpenseRow)
        /// Pre-filled from the Chosen Proposal; saving retires the Proposal.
        case convert(ProposalRow)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let expense): expense.id.uuidString
            case .convert(let proposal): proposal.id.uuidString
            }
        }
    }

    @Environment(GroupsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    let activityID: UUID
    let mode: Mode

    @State private var title = ""
    @State private var amountText = ""
    @State private var date = Date()
    @State private var paidBy: UUID?
    @State private var isExact = false
    @State private var included: Set<UUID> = []
    @State private var exactTexts: [UUID: String] = [:]
    @State private var hasServiceCharge = false
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Group {
                if let context = model.context(groupID) {
                    form(context)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存", action: save)
                        .disabled(checked == nil || isWorking)
                        .needsConnection()
                }
            }
            .onAppear(perform: prefill)
            .failureAlert($failure)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .new: "記一筆開支"
        case .edit: "改開支"
        case .convert: "轉做開支"
        }
    }

    private func form(_ context: GroupContext) -> some View {
        Form {
            Section {
                TextField("買咗乜", text: $title)
                LabeledContent("金額") { AmountField(title: "$0", text: $amountText) }
                DatePicker("日期", selection: $date, displayedComponents: .date)
                Picker("邊個畀錢", selection: $paidBy) {
                    ForEach(context.snapshot.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            } footer: {
                if case .convert = mode { Text("資料由選定提案預先填好。改返實際金額同邊個畀錢就得。") }
            }

            Section {
                Toggle("加一服務費", isOn: $hasServiceCharge)
            } footer: {
                Text("照餐牌價入數，開咗之後每人份額會加 10%。")
            }

            Section {
                Picker("分法", selection: $isExact) {
                    Text("平均分").tag(false)
                    Text("逐人金額").tag(true)
                }
                .pickerStyle(.segmented)
                ForEach(context.snapshot.members) { member in
                    if isExact {
                        LabeledContent(member.name) {
                            AmountField(title: "$0", text: Binding(
                                get: { exactTexts[member.id] ?? "" }, set: { exactTexts[member.id] = $0 }))
                        }
                    } else {
                        Toggle(member.name, isOn: Binding(
                            get: { included.contains(member.id) },
                            set: { if $0 { included.insert(member.id) } else { included.remove(member.id) } }))
                    }
                }
            } header: {
                Text("邊啲人有份")
            } footer: {
                if let problem { Text(problem).foregroundStyle(.red) }
            }

            if let expense = checked?.expense {
                Section("每人份額") {
                    ForEach(context.snapshot.members.filter { expense.shares[$0.id.memberID] != nil }) { member in
                        LabeledContent(member.name, value: expense.shares[member.id.memberID]!.description)
                    }
                    LabeledContent("實際總數", value: expense.total.description).fontWeight(.semibold)
                }
            }
        }
    }

    /// What is being entered, as the Ledger would hold it. Building it runs every Ledger rule.
    private var draft: Result<(input: GroupsService.ExpenseInput, expense: Expense), LedgerError>? {
        guard !title.trimmed.isEmpty, let amount = Money(typed: amountText), let paidBy else { return nil }
        let split: SplitRow
        if isExact {
            var amounts: [UUID: Money] = [:]
            for (member, text) in exactTexts where !text.trimmed.isEmpty {
                guard let money = Money(typed: text) else { return nil }
                amounts[member] = money
            }
            split = .exact(amounts)
        } else {
            split = .equal(Array(included))
        }
        let input = GroupsService.ExpenseInput(
            title: title.trimmed, date: Day(date), amount: amount, paidBy: paidBy, split: split,
            hasServiceCharge: hasServiceCharge)
        do {
            let expense = try Expense(
                id: "draft", activityID: activityID.activityID, title: input.title, date: date, amount: amount,
                paidBy: paidBy.memberID, split: split.ledger, hasServiceCharge: hasServiceCharge)
            return .success((input, expense))
        } catch let error as LedgerError {
            return .failure(error)
        } catch {
            return nil
        }
    }

    private var checked: (input: GroupsService.ExpenseInput, expense: Expense)? {
        if case .success(let value) = draft { value } else { nil }
    }

    /// Why the Expense cannot be saved yet, in the user's terms.
    private var problem: String? {
        guard case .failure(let error) = draft else { return nil }
        switch error {
        case .noParticipants:
            return isExact ? "未入任何人嘅金額。" : "最少要揀一個有份嘅人。"
        case .exactAmountsMismatch(let difference):
            return difference > .zero
                ? "逐人金額加埋比總數少咗 \(difference.description)。"
                : "逐人金額加埋比總數多咗 \((-difference).description)。"
        default:
            return "金額唔啱。"
        }
    }

    private func prefill() {
        guard paidBy == nil, let context = model.context(groupID) else { return }
        switch mode {
        case .new:
            paidBy = context.me?.id ?? context.snapshot.members.first?.id
            included = Set(context.snapshot.members.map(\.id))
            if let day = context.activity(activityID)?.date { date = day.date() }
        case .edit(let expense):
            title = expense.title
            amountText = Money(cents: expense.amountCents).plain
            date = expense.date.date()
            paidBy = expense.paidBy
            hasServiceCharge = expense.hasServiceCharge
            isExact = expense.split.isExact
            included = Set(expense.split.participants)
            for (key, cents) in expense.split.amounts ?? [:] {
                if let member = UUID(uuidString: key) { exactTexts[member] = Money(cents: cents).plain }
            }
        case .convert(let proposal):
            paidBy = context.me?.id ?? context.snapshot.members.first?.id
            if let day = context.activity(activityID)?.date { date = day.date() }
            if let draft = try? context.state.expenseDraft(for: proposal.proposalID) {
                title = draft.title
                amountText = draft.amount.plain
                included = Set(draft.participants.compactMap(\.uuid))
            }
        }
    }

    private func save() {
        guard let input = checked?.input else { return }
        isWorking = true
        Task {
            do {
                try await model.change(groupID) { service in
                    switch mode {
                    case .new:
                        try await service.addExpense(input, to: activityID, in: groupID)
                    case .edit(let expense):
                        try await service.updateExpense(expense.id, to: input)
                    case .convert(let proposal):
                        try await service.addExpense(input, to: activityID, in: groupID, from: proposal.id)
                    }
                }
                dismiss()
            } catch {
                failure = failureMessage(error)
            }
            isWorking = false
        }
    }
}
