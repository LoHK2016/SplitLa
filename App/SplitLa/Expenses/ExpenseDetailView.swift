import Ledger
import SwiftUI

/// One Expense in full: how it was split, each Share, and every change ever made to it.
struct ExpenseDetailView: View {
    @Environment(GroupsModel.self) private var model
    let groupID: UUID
    let expenseID: UUID

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var failure: String?

    var body: some View {
        Group {
            if let context = model.context(groupID),
               let expense = context.snapshot.expenses.first(where: { $0.id == expenseID }) {
                list(context, expense)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Expense")
        .navigationBarTitleDisplayMode(.inline)
        .failureAlert($failure)
    }

    private func list(_ context: GroupContext, _ expense: ExpenseRow) -> some View {
        List {
            if expense.isDeleted {
                Section {
                    Label("This Expense was deleted and no longer counts towards Balances.", systemImage: "trash").foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent("Name", value: expense.title)
                LabeledContent("Activity", value: context.activity(expense.activityId)?.name ?? "")
                LabeledContent("Date", value: expense.date.display)
                LabeledContent("Paid by", value: context.name(of: expense.paidBy))
                LabeledContent("Amount", value: Money(cents: expense.amountCents).description)
                LabeledContent("Split", value: expense.split.isExact ? String(localized: "Exact amounts") : String(localized: "Equally"))
                LabeledContent("10% service charge", value: expense.hasServiceCharge ? String(localized: "Yes") : String(localized: "No"))
                if expense.proposalId != nil { LabeledContent("From", value: String(localized: "Chosen Proposal")) }
            }
            if let ledger = expense.ledger {
                Section("Shares") {
                    ForEach(context.snapshot.members.filter { ledger.shares[$0.id.memberID] != nil }) { member in
                        LabeledContent(member.name, value: ledger.shares[member.id.memberID]!.description)
                    }
                    LabeledContent("Total paid", value: ledger.total.description).fontWeight(.semibold)
                }
            }
            HistorySection(entity: expenseID, context: context, version: expense.hashValue)
        }
        .toolbar {
            if !expense.isDeleted {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Edit", systemImage: "pencil") { isEditing = true }
                        .needsConnection()
                    Button("Delete", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                        .needsConnection()
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ExpenseFormView(groupID: groupID, activityID: expense.activityId, mode: .edit(expense))
        }
        .confirmationDialog("Delete this Expense?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Expense", role: .destructive) {
                Task {
                    do {
                        try await model.change(groupID) { try await $0.deleteExpense(expenseID) }
                    } catch {
                        failure = failureMessage(error)
                    }
                }
            }
            .needsConnection()
        } message: {
            Text("It will stop counting towards Balances, but stays in the history so the whole Group can see who deleted it.")
        }
    }
}
