import Ledger
import SwiftUI

/// The private side of SplitLa: the Personal Budget, and this month's Committed Spend item by item.
struct PersonalBudgetView: View {
    @Environment(GroupsModel.self) private var model
    @Environment(PersonalBudgetStore.self) private var store

    @State private var isEditing = false
    @State private var budgetText = ""
    @State private var invalid = false

    var body: some View {
        let month = YearMonth(Date(), calendar: .current)
        let committed = committedSpend(for: model.identity, in: month, across: model.allStates, calendar: .current)
        List {
            Section {
                LabeledContent("Monthly Personal Budget", value: store.budget?.description ?? String(localized: "Not set"))
                Button(store.budget == nil ? "Set Personal Budget" as LocalizedStringKey : "Change Personal Budget") {
                    budgetText = store.budget?.plain ?? ""
                    isEditing = true
                }
                if store.budget != nil {
                    Button("Remove Personal Budget", role: .destructive) { store.set(nil) }
                }
            } footer: {
                Text("Your monthly limit for social spending, across all your Groups. It stays on this iPhone: other Members and SplitLa’s servers can’t see it, and nobody can tell whether you go over.")
            }

            Section {
                LabeledContent("Committed Spend", value: committed.total.description)
                if let budget = store.budget {
                    let remaining = committed.remaining(of: budget)
                    LabeledContent(remaining < .zero ? "Over by" as LocalizedStringKey : "Left") {
                        Text((remaining < .zero ? -remaining : remaining).description)
                            .foregroundStyle(remaining < .zero ? .red : .primary)
                            .fontWeight(remaining < .zero ? .semibold : .regular)
                    }
                }
            } header: {
                Text(Calendar.current.date(from: DateComponents(year: month.year, month: month.month)) ?? Date(), format: .dateTime.year().month(.wide))
            } footer: {
                Text("Your Shares of Expenses so far, plus your Shares of Chosen Proposals for Activities you’re going to.")
            }

            Section("What Makes It Up") {
                if committed.items.isEmpty {
                    Text("No Expenses or Chosen Proposals this month yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(committed.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(activityName(item.activityID)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .chosenProposal = item.source { Tag("Chosen Proposal", tint: .green) }
                        Text(item.amount.description)
                    }
                }
            }
        }
        .navigationTitle("Personal Budget")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Monthly Personal Budget", isPresented: $isEditing) {
            TextField("Monthly limit", text: $budgetText).keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let budget = Money(typed: budgetText) { store.set(budget) } else { invalid = true }
            }
        } message: {
            Text("Stays on this iPhone only.")
        }
        .alert("Enter a valid amount.", isPresented: $invalid) { Button("OK") {} }
    }

    /// "Activity · Group" for a Committed Spend item.
    private func activityName(_ id: ActivityID) -> String {
        for snapshot in model.snapshots.values {
            if let activity = snapshot.activities.first(where: { $0.id.activityID == id }) {
                return "\(activity.name) · \(snapshot.group.name)"
            }
        }
        return ""
    }
}
