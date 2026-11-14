import Ledger
import SwiftUI

/// Sheet for opening a Proposal: a name and an estimate, per person or for everyone.
struct ProposalFormView: View {
    @Environment(GroupsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    let activityID: UUID

    @State private var title = ""
    @State private var isPerPerson = true
    @State private var amountText = ""
    @State private var isWorking = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("提案") {
                    TextField("例如：餐廳 A", text: $title)
                }
                Section {
                    Picker("金額係", selection: $isPerPerson) {
                        Text("每人").tag(true)
                        Text("總數").tag(false)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent(isPerPerson ? "每人預計" : "總共預計") {
                        AmountField(title: "$0", text: $amountText)
                    }
                } footer: {
                    Text(isPerPerson ? "每個去嘅人畀呢個數。" : "由覆咗「去」嘅人平均分。")
                }
            }
            .navigationTitle("開新提案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("建立", action: create)
                        .disabled(title.trimmed.isEmpty || Money(typed: amountText) == nil || isWorking)
                        .needsConnection()
                }
            }
            .failureAlert($failure)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private func create() {
        guard let amount = Money(typed: amountText) else { return }
        isWorking = true
        Task {
            do {
                try await model.change(groupID) {
                    try await $0.addProposal(
                        titled: title.trimmed, amount: isPerPerson ? .perPerson(amount) : .total(amount),
                        to: activityID, in: groupID)
                }
                dismiss()
            } catch {
                failure = failureMessage(error)
            }
            isWorking = false
        }
    }
}
