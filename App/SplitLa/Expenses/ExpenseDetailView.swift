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
        .navigationTitle("開支")
        .navigationBarTitleDisplayMode(.inline)
        .failureAlert($failure)
    }

    private func list(_ context: GroupContext, _ expense: ExpenseRow) -> some View {
        List {
            if expense.isDeleted {
                Section {
                    Label("呢筆開支已經刪除，唔再計入結餘。", systemImage: "trash").foregroundStyle(.red)
                }
            }
            Section {
                LabeledContent("名稱", value: expense.title)
                LabeledContent("活動", value: context.activity(expense.activityId)?.name ?? "")
                LabeledContent("日期", value: expense.date.display)
                LabeledContent("畀錢", value: context.name(of: expense.paidBy))
                LabeledContent("金額", value: Money(cents: expense.amountCents).description)
                LabeledContent("分法", value: expense.split.isExact ? "逐人金額" : "平均分")
                LabeledContent("加一服務費", value: expense.hasServiceCharge ? "有" : "冇")
                if expense.proposalId != nil { LabeledContent("來源", value: "由選定提案轉過嚟") }
            }
            if let ledger = expense.ledger {
                Section("每人份額") {
                    ForEach(context.snapshot.members.filter { ledger.shares[$0.id.memberID] != nil }) { member in
                        LabeledContent(member.name, value: ledger.shares[member.id.memberID]!.description)
                    }
                    LabeledContent("實際總數", value: ledger.total.description).fontWeight(.semibold)
                }
            }
            HistorySection(entity: expenseID, context: context, version: expense.hashValue)
        }
        .toolbar {
            if !expense.isDeleted {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("改", systemImage: "pencil") { isEditing = true }
                        .needsConnection()
                    Button("刪除", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                        .needsConnection()
                }
            }
        }
        .sheet(isPresented: $isEditing) {
            ExpenseFormView(groupID: groupID, activityID: expense.activityId, mode: .edit(expense))
        }
        .confirmationDialog("刪除呢筆開支？", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("刪除開支", role: .destructive) {
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
            Text("佢唔會再計入結餘，但係仍然會留喺記錄度，全組都見到係邊個刪。")
        }
    }
}
