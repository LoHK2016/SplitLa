import Ledger
import SwiftUI

/// What a new Settlement starts from, usually one of the suggested transfers.
struct SettlementDraft: Identifiable {
    let id = UUID()
    var from: UUID?
    var to: UUID?
    var amount: Money?
    /// Set when changing a Settlement already recorded.
    var existing: SettlementRow?
}

/// Every Settlement recorded in the Group, deleted ones included.
struct SettlementsView: View {
    @Environment(GroupsModel.self) private var model
    let groupID: UUID

    @State private var draft: SettlementDraft?

    var body: some View {
        Group {
            if let context = model.context(groupID) {
                List {
                    Section {
                        ForEach(context.snapshot.settlements.reversed()) { settlement in
                            Button {
                                draft = SettlementDraft(existing: settlement)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(context.name(of: settlement.fromMember)) paid \(context.name(of: settlement.toMember))")
                                            .strikethrough(settlement.isDeleted)
                                        Text(settlement.date.display).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if settlement.isDeleted {
                                        Tag("Deleted", tint: .red)
                                    } else {
                                        Text(Money(cents: settlement.amountCents).description)
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                        Button("Record a Settlement", systemImage: "plus") { draft = SettlementDraft() }
                            .needsConnection()
                    } footer: {
                        Text("Settlements are only records. SplitLa doesn’t move money or connect to FPS or PayMe.")
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Settlements")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $draft) { SettlementFormView(groupID: groupID, draft: $0) }
    }
}

/// Sheet for recording a Settlement or changing one. Shows its history when it already exists.
struct SettlementFormView: View {
    @Environment(GroupsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    let draft: SettlementDraft

    @State private var from: UUID?
    @State private var to: UUID?
    @State private var amountText = ""
    @State private var date = Date()
    @State private var isWorking = false
    @State private var failure: String?

    private var isDeleted: Bool { draft.existing?.isDeleted ?? false }

    var body: some View {
        NavigationStack {
            Group {
                if let context = model.context(groupID) {
                    form(context)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(draft.existing == nil ? "Record a Settlement" as LocalizedStringKey : "Settlement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if !isDeleted {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .disabled(!isValid || isWorking)
                            .needsConnection()
                    }
                }
            }
            .onAppear(perform: prefill)
            .failureAlert($failure)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func form(_ context: GroupContext) -> some View {
        Form {
            if isDeleted {
                Section {
                    Label("This Settlement was deleted and no longer counts towards Balances.", systemImage: "trash").foregroundStyle(.red)
                }
            }
            Section {
                Picker("Paid by", selection: $from) {
                    ForEach(context.snapshot.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("Paid to", selection: $to) {
                    ForEach(context.snapshot.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                LabeledContent("Amount") { AmountField(title: "$0", text: $amountText) }
                DatePicker("Date", selection: $date, displayedComponents: .date)
            } footer: {
                if from != nil && from == to {
                    Text("The payer and the person paid can’t be the same.").foregroundStyle(.red)
                } else {
                    Text("Records money already paid outside the app. SplitLa doesn’t handle real money.")
                }
            }
            .disabled(isDeleted)

            if let existing = draft.existing {
                if !isDeleted {
                    Section {
                        Button("Delete Settlement", systemImage: "trash", role: .destructive) {
                            run { try await $0.deleteSettlement(existing.id) }
                        }
                        .needsConnection()
                    }
                }
                HistorySection(entity: existing.id, context: context, version: 0)
            }
        }
    }

    private var isValid: Bool {
        guard let from, let to, from != to, let amount = Money(typed: amountText) else { return false }
        return amount > .zero
    }

    private func prefill() {
        guard from == nil, to == nil else { return }
        if let existing = draft.existing {
            (from, to, date) = (existing.fromMember, existing.toMember, existing.date.date())
            amountText = Money(cents: existing.amountCents).plain
        } else {
            let context = model.context(groupID)
            from = draft.from ?? context?.me?.id
            to = draft.to ?? context?.snapshot.members.first { $0.id != from }?.id
            amountText = draft.amount?.plain ?? ""
        }
    }

    private func save() {
        guard let from, let to, let amount = Money(typed: amountText) else { return }
        let day = Day(date)
        run { service in
            if let existing = draft.existing {
                try await service.updateSettlement(existing.id, from: from, to: to, amount: amount, on: day)
            } else {
                try await service.addSettlement(from: from, to: to, amount: amount, on: day, in: groupID)
            }
        }
    }

    private func run(_ work: @escaping (GroupsService) async throws -> Void) {
        isWorking = true
        Task {
            do {
                try await model.change(groupID, work)
                dismiss()
            } catch {
                failure = failureMessage(error)
            }
            isWorking = false
        }
    }
}
