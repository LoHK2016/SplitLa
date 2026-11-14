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
    @State private var splitMode = SplitMode.equal
    @State private var included: Set<UUID> = []
    @State private var exactTexts: [UUID: String] = [:]
    @State private var hasServiceCharge = false
    /// Plate prices as typed, one per kind of plate, for splitting by plates.
    @State private var plateTexts: [String] = PlatePrices.remembered.map(\.plain)
    @State private var plates = PlateTally(prices: [])

    /// How the Expense is divided. By plates is a way of filling in exact amounts: it is saved as one.
    enum SplitMode: Hashable { case equal, exact, plates }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(checked == nil || isWorking)
                        .needsConnection()
                }
            }
            .onAppear(perform: prefill)
            .failureAlert($failure)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private var navigationTitle: LocalizedStringKey {
        switch mode {
        case .new: "New Expense"
        case .edit: "Edit Expense"
        case .convert: "Turn into Expense"
        }
    }

    private func form(_ context: GroupContext) -> some View {
        Form {
            Section {
                TextField("What was it for?", text: $title)
                if splitMode == .plates {
                    LabeledContent("Amount", value: (tally?.total ?? .zero).description)
                } else {
                    LabeledContent("Amount") { AmountField(title: "$0", text: $amountText) }
                }
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Paid by", selection: $paidBy) {
                    ForEach(context.snapshot.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
            } footer: {
                if case .convert = mode { Text("Filled in from the Chosen Proposal. Just correct the real amount and who paid.") }
            }

            Section {
                Toggle("10% service charge", isOn: $hasServiceCharge)
            } footer: {
                Text("Enter menu prices; each Share gets 10% added.")
            }

            if splitMode == .plates {
                PlatePricesSection(texts: $plateTexts)
            }

            Section {
                Picker("Split", selection: $splitMode) {
                    Text("Equally").tag(SplitMode.equal)
                    Text("Exact amounts").tag(SplitMode.exact)
                    Text("By plates").tag(SplitMode.plates)
                }
                .pickerStyle(.segmented)
                ForEach(context.snapshot.members) { member in
                    if splitMode == .plates {
                        PlateCounter(
                            name: member.name, member: member.id.memberID, prices: platePrices ?? [],
                            plates: $plates)
                    } else if splitMode == .exact {
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
                Text("Who Shares It")
            } footer: {
                if let problem {
                    Text(problem).foregroundStyle(.red)
                } else if splitMode == .plates {
                    Text("Tap + for each plate someone took. Their amount is worked out from the plate prices.")
                }
            }

            if let expense = checked?.expense {
                Section("Shares") {
                    ForEach(context.snapshot.members.filter { expense.shares[$0.id.memberID] != nil }) { member in
                        LabeledContent(member.name, value: expense.shares[member.id.memberID]!.description)
                    }
                    LabeledContent("Total paid", value: expense.total.description).fontWeight(.semibold)
                }
            }
        }
    }

    /// What is being entered, as the Ledger would hold it. Building it runs every Ledger rule.
    private var draft: Result<(input: GroupsService.ExpenseInput, expense: Expense), LedgerError>? {
        guard !title.trimmed.isEmpty, let paidBy else { return nil }
        let amount: Money
        let split: SplitRow
        if splitMode == .plates {
            guard let tally else { return nil }
            amount = tally.total
            split = .exact(Dictionary(uniqueKeysWithValues: tally.amounts.compactMap { member, money in
                member.uuid.map { ($0, money) }
            }))
        } else if splitMode == .exact {
            guard let typed = Money(typed: amountText) else { return nil }
            amount = typed
            var amounts: [UUID: Money] = [:]
            for (member, text) in exactTexts where !text.trimmed.isEmpty {
                guard let money = Money(typed: text) else { return nil }
                amounts[member] = money
            }
            split = .exact(amounts)
        } else {
            guard let typed = Money(typed: amountText) else { return nil }
            amount = typed
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
            switch splitMode {
            case .equal: return String(localized: "Pick at least one person.")
            case .exact: return String(localized: "No amounts entered yet.")
            case .plates: return String(localized: "Count at least one plate.")
            }
        case .exactAmountsMismatch(let difference):
            return difference > .zero
                ? String(localized: "The exact amounts come to \(difference.description) less than the total.")
                : String(localized: "The exact amounts come to \((-difference).description) more than the total.")
        default:
            return String(localized: "That amount isn’t right.")
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
            splitMode = expense.split.isExact ? .exact : .equal
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

    /// The plate prices as typed, or nil while one of them is not a valid amount.
    private var platePrices: [Money]? {
        let prices = plateTexts.map(Money.init(typed:))
        return prices.contains(nil) ? nil : prices.compactMap { $0 }
    }

    /// The plates counted so far, at the current prices.
    private var tally: PlateTally? {
        guard let platePrices else { return nil }
        var current = plates
        current.prices = platePrices
        return current
    }

    private func save() {
        guard let input = checked?.input else { return }
        if splitMode == .plates, let platePrices { PlatePrices.remembered = platePrices }
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
