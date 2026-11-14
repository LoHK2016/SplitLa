import Ledger
import SwiftUI

/// Where a tap can lead from the Group list.
enum Route: Hashable {
    case group(UUID)
    case activity(group: UUID, activity: UUID)
    case expense(group: UUID, expense: UUID)
    case settlements(group: UUID)
    case personalBudget
}

extension UUID {
    var activityID: ActivityID { ActivityID(uuidString.lowercased()) }
    var proposalID: ProposalID { ProposalID(uuidString.lowercased()) }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension Day {
    /// "2026年12月5日" in the user's own format.
    var display: String { date().formatted(date: .abbreviated, time: .omitted) }
}

/// A Balance in words: who is owed, who owes.
struct BalanceText: View {
    let balance: Money

    var body: some View {
        if balance > .zero {
            Text("攞返 \((balance).description)").foregroundStyle(.green)
        } else if balance < .zero {
            Text("要畀 \((-balance).description)").foregroundStyle(.red)
        } else {
            Text("找清").foregroundStyle(.secondary)
        }
    }
}

/// A small label beside a name or title.
struct Tag: View {
    let text: String
    var tint: Color = .secondary

    init(_ text: String, tint: Color = .secondary) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }
}

/// Field for typing an amount in dollars.
struct AmountField: View {
    let title: String
    @Binding var text: String

    var body: some View {
        TextField(title, text: $text)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
    }
}

private struct NeedsConnection: ViewModifier {
    @Environment(GroupsModel.self) private var model

    func body(content: Content) -> some View {
        content.disabled(model.isOffline)
    }
}

private struct FailureAlert: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.alert("做唔到", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") {}
        } message: {
            Text(message ?? "")
        }
    }
}

extension View {
    /// For anything that adds or changes data: switched off while offline.
    func needsConnection() -> some View { modifier(NeedsConnection()) }

    /// Tells the user when a change could not be made.
    func failureAlert(_ message: Binding<String?>) -> some View { modifier(FailureAlert(message: message)) }
}

/// What to tell the user when a change fails.
func failureMessage(_ error: any Error) -> String {
    error is URLError ? "連唔到伺服器，請檢查網絡再試。" : "伺服器唔接受呢個改動，請更新畫面再試。"
}

/// Shown across the app while there is no connection.
struct OfflineBanner: View {
    var body: some View {
        Label("離線緊：只可以睇上次同步嘅資料，暫時改唔到嘢。", systemImage: "wifi.slash")
            .font(.footnote)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal)
            .background(.yellow.opacity(0.9))
            .foregroundStyle(.black)
    }
}

/// The history of one Expense or Settlement: who did what, when, and what changed.
struct HistorySection: View {
    @Environment(GroupsModel.self) private var model
    let entity: UUID
    let context: GroupContext
    /// Changes whenever the entity does, so the history is read again.
    let version: Int

    @State private var changes: [ChangeRow]?

    var body: some View {
        Section("改動記錄") {
            if let changes {
                ForEach(changes) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("\(change.actorName.isEmpty ? "有人" : change.actorName) \(verb(change.action))")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(change.at.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(differences(change), id: \.self) { line in
                            Text(line).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task(id: version) {
            if let latest = try? await model.service.history(of: entity) { changes = latest }
        }
    }

    private func verb(_ action: String) -> String {
        switch action {
        case "created": "新增咗"
        case "deleted": "刪除咗"
        case "restored": "還原咗"
        default: "改咗"
        }
    }

    private func differences(_ change: ChangeRow) -> [String] {
        switch (change.before, change.after) {
        case (.expense(let old)?, .expense(let new)) where change.action == "updated":
            var lines: [String] = []
            if old.title != new.title { lines.append("名稱：\(old.title) → \(new.title)") }
            if old.amountCents != new.amountCents {
                lines.append("金額：\(Money(cents: old.amountCents)) → \(Money(cents: new.amountCents))")
            }
            if old.date != new.date { lines.append("日期：\(old.date.display) → \(new.date.display)") }
            if old.paidBy != new.paidBy {
                lines.append("畀錢：\(context.name(of: old.paidBy)) → \(context.name(of: new.paidBy))")
            }
            if old.split != new.split { lines.append("分法：\(describe(old.split)) → \(describe(new.split))") }
            if old.hasServiceCharge != new.hasServiceCharge {
                lines.append("加一：\(old.hasServiceCharge ? "有" : "冇") → \(new.hasServiceCharge ? "有" : "冇")")
            }
            return lines
        case (.settlement(let old)?, .settlement(let new)) where change.action == "updated":
            var lines: [String] = []
            if old.amountCents != new.amountCents {
                lines.append("金額：\(Money(cents: old.amountCents)) → \(Money(cents: new.amountCents))")
            }
            if old.fromMember != new.fromMember || old.toMember != new.toMember {
                lines.append("\(context.name(of: old.fromMember)) 畀 \(context.name(of: old.toMember)) → \(context.name(of: new.fromMember)) 畀 \(context.name(of: new.toMember))")
            }
            if old.date != new.date { lines.append("日期：\(old.date.display) → \(new.date.display)") }
            return lines
        case (nil, .expense(let new)):
            return ["\(new.title)，\(Money(cents: new.amountCents))，\(context.name(of: new.paidBy)) 畀錢"]
        case (nil, .settlement(let new)):
            return ["\(context.name(of: new.fromMember)) 畀 \(context.name(of: new.toMember)) \(Money(cents: new.amountCents))"]
        default:
            return []
        }
    }

    private func describe(_ split: SplitRow) -> String {
        if split.isExact {
            return "逐人金額（" + (split.amounts ?? [:]).sorted { $0.key < $1.key }.map {
                "\(UUID(uuidString: $0.key).map(context.name(of:)) ?? "？") \(Money(cents: $0.value))"
            }.joined(separator: "、") + "）"
        }
        return "平均分（" + (split.members ?? []).map(context.name(of:)).joined(separator: "、") + "）"
    }
}
