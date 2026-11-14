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
                Section("Proposal") {
                    TextField("e.g. Restaurant A", text: $title)
                }
                Section {
                    Picker("Amount is", selection: $isPerPerson) {
                        Text("Per person").tag(true)
                        Text("Total").tag(false)
                    }
                    .pickerStyle(.segmented)
                    LabeledContent(isPerPerson ? "Amount per person" as LocalizedStringKey : "Amount in total") {
                        AmountField(title: "$0", text: $amountText)
                    }
                } footer: {
                    Text(isPerPerson ? "Everyone going pays this." as LocalizedStringKey : "Split evenly among everyone going.")
                }
            }
            .navigationTitle("New Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
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
