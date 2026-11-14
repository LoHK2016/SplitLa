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
                                        Text("\(context.name(of: settlement.fromMember)) 畀 \(context.name(of: settlement.toMember))")
                                            .strikethrough(settlement.isDeleted)
                                        Text(settlement.date.display).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if settlement.isDeleted {
                                        Tag("已刪除", tint: .red)
                                    } else {
                                        Text(Money(cents: settlement.amountCents).description)
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                        Button("記一筆找數", systemImage: "plus") { draft = SettlementDraft() }
                            .needsConnection()
                    } footer: {
                        Text("找數只係記錄。SplitLa 唔會幫你過數，亦唔會連去 FPS 或 PayMe。")
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("找數記錄")
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
            .navigationTitle(draft.existing == nil ? "記一筆找數" : "找數")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                if !isDeleted {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("儲存", action: save)
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
                    Label("呢筆找數已經刪除，唔再計入結餘。", systemImage: "trash").foregroundStyle(.red)
                }
            }
            Section {
                Picker("邊個畀錢", selection: $from) {
                    ForEach(context.snapshot.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("畀邊個", selection: $to) {
                    ForEach(context.snapshot.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                LabeledContent("金額") { AmountField(title: "$0", text: $amountText) }
                DatePicker("日期", selection: $date, displayedComponents: .date)
            } footer: {
                if from != nil && from == to {
                    Text("畀錢同收錢唔可以係同一個人。").foregroundStyle(.red)
                } else {
                    Text("記低已經喺 App 以外畀咗嘅錢。SplitLa 唔處理真錢。")
                }
            }
            .disabled(isDeleted)

            if let existing = draft.existing {
                if !isDeleted {
                    Section {
                        Button("刪除呢筆找數", systemImage: "trash", role: .destructive) {
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
