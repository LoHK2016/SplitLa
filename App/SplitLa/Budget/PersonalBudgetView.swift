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
                LabeledContent("每月個人預算", value: store.budget?.description ?? "未定")
                Button(store.budget == nil ? "定個人預算" : "改個人預算") {
                    budgetText = store.budget?.plain ?? ""
                    isEditing = true
                }
                if store.budget != nil {
                    Button("移除個人預算", role: .destructive) { store.set(nil) }
                }
            } footer: {
                Text("你每個月社交開支嘅上限，跨晒所有群組。只儲喺呢部機：其他成員同 SplitLa 嘅伺服器都睇唔到，亦唔會知你有冇超支。")
            }

            Section {
                LabeledContent("已承諾開支", value: committed.total.description)
                if let budget = store.budget {
                    let remaining = budget - committed.total
                    LabeledContent(remaining < .zero ? "超支" : "仲剩") {
                        Text((remaining < .zero ? -remaining : remaining).description)
                            .foregroundStyle(remaining < .zero ? .red : .primary)
                            .fontWeight(remaining < .zero ? .semibold : .regular)
                    }
                }
            } header: {
                Text("\(String(month.year))年\(month.month)月")
            } footer: {
                Text("已經發生嘅開支入面你嘅份額，加埋你覆咗「去」嘅活動入面選定提案嘅份額。")
            }

            Section("由邊幾筆組成") {
                if committed.items.isEmpty {
                    Text("今個月未有任何開支或者選定提案。").foregroundStyle(.secondary)
                }
                ForEach(Array(committed.items.enumerated()), id: \.offset) { _, item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title)
                            Text(activityName(item.activityID)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if case .chosenProposal = item.source { Tag("選定提案", tint: .green) }
                        Text(item.amount.description)
                    }
                }
            }
        }
        .navigationTitle("個人預算")
        .navigationBarTitleDisplayMode(.inline)
        .alert("每月個人預算", isPresented: $isEditing) {
            TextField("每月上限", text: $budgetText).keyboardType(.decimalPad)
            Button("取消", role: .cancel) {}
            Button("儲存") {
                if let budget = Money(typed: budgetText) { store.set(budget) } else { invalid = true }
            }
        } message: {
            Text("只儲喺呢部機。")
        }
        .alert("請入一個有效嘅金額。", isPresented: $invalid) { Button("好") {} }
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
