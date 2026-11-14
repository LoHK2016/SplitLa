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
                if let budget = store.budget {
                    BudgetRing(month: month, budget: budget, committed: committed)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)
                        Text("Set a monthly limit and every Proposal will show what you’d have left.")
                            .multilineTextAlignment(.center)
                        Button("Set Personal Budget") { edit() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }

            Section {
                Label {
                    Text("Your monthly limit for social spending, across all your Groups. It stays on this iPhone: other Members and SplitLa’s servers can’t see it, and nobody can tell whether you go over.")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "lock").foregroundStyle(Color.accentColor)
                }
                .listRowBackground(Color.accentColor.opacity(0.10))
            }

            Section {
                if committed.items.isEmpty {
                    Text("No Expenses or Chosen Proposals this month yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(committed.items.enumerated()), id: \.offset) { _, item in
                    HStack(spacing: 12) {
                        let isProposal = if case .chosenProposal = item.source { true } else { false }
                        Image(systemName: isProposal ? "checkmark.seal" : "receipt")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 40, height: 40)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityLabel(isProposal ? "Chosen Proposal" : "Expense")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.headline)
                            Text(activityName(item.activityID)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.amount.description)
                            .font(.system(.body, design: .rounded).weight(.bold))
                            .monospacedDigit()
                    }
                }
            } header: {
                Text("What Makes It Up")
            } footer: {
                Text("Your Shares of Expenses so far, plus your Shares of Chosen Proposals for Activities you’re going to.")
            }

            if store.budget != nil {
                Section {
                    Button("Change Personal Budget") { edit() }
                    Button("Remove Personal Budget", role: .destructive) { store.set(nil) }
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

    private func edit() {
        budgetText = store.budget?.plain ?? ""
        isEditing = true
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

/// This month at a glance: a ring filling up as the Personal Budget is committed, what is left
/// in the middle, and the two figures behind it.
private struct BudgetRing: View {
    let month: YearMonth
    let budget: Money
    let committed: CommittedSpend

    var body: some View {
        let remaining = committed.remaining(of: budget)
        let used = committed.fractionUsed(of: budget)
        let isOver = remaining < .zero
        VStack(spacing: 16) {
            Text(Calendar.current.date(from: DateComponents(year: month.year, month: month.month)) ?? Date(),
                 format: .dateTime.year().month(.wide))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ZStack {
                Circle().stroke(Color(.tertiarySystemFill), lineWidth: 18)
                Circle()
                    .trim(from: 0, to: min(used, 1))
                    .stroke(isOver ? Color.red : Color.accentColor, style: StrokeStyle(lineWidth: 18, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(isOver ? "Over by" : "Left").font(.footnote).foregroundStyle(.secondary)
                    Text((isOver ? -remaining : remaining).description)
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .foregroundStyle(isOver ? Color.red : .primary)
                    Text("Budget \(budget.description)").font(.footnote).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)
            }
            .frame(width: 200, height: 200)
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                Figure(title: "Committed Spend", value: Text(committed.total.description))
                Figure(title: "Used", value: Text(used, format: .percent.precision(.fractionLength(0))))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

private struct Figure: View {
    let title: LocalizedStringKey
    let value: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            value.font(.system(.title3, design: .rounded).weight(.heavy)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 14))
    }
}
