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
            Text("Gets back \(balance.description)").foregroundStyle(.green)
        } else if balance < .zero {
            Text("Owes \((-balance).description)").foregroundStyle(.red)
        } else {
            Text("Settled").foregroundStyle(.secondary)
        }
    }
}

/// A small label beside a name or title.
struct Tag: View {
    let text: LocalizedStringKey
    var tint: Color = .secondary

    init(_ text: LocalizedStringKey, tint: Color = .secondary) {
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
        content.alert("Couldn’t Do That", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
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
    error is URLError
        ? String(localized: "Can’t reach the server. Check your connection and try again.")
        : String(localized: "The server didn’t accept this change. Refresh and try again.")
}

/// Shown across the app while there is no connection.
struct OfflineBanner: View {
    var body: some View {
        Label("Offline: showing your last synced data. Changes are paused.", systemImage: "wifi.slash")
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
        Section("History") {
            if let changes {
                ForEach(changes) { change in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(headline(change))
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

    private func headline(_ change: ChangeRow) -> String {
        let who = change.actorName.isEmpty ? String(localized: "Someone") : change.actorName
        switch change.action {
        case "created": return String(localized: "\(who) added it")
        case "deleted": return String(localized: "\(who) deleted it")
        case "restored": return String(localized: "\(who) restored it")
        default: return String(localized: "\(who) changed it")
        }
    }

    private func differences(_ change: ChangeRow) -> [String] {
        switch (change.before, change.after) {
        case (.expense(let old)?, .expense(let new)) where change.action == "updated":
            var lines: [String] = []
            if old.title != new.title { lines.append(String(localized: "Name: \(old.title) → \(new.title)")) }
            if old.amountCents != new.amountCents {
                lines.append(String(localized: "Amount: \(Money(cents: old.amountCents).description) → \(Money(cents: new.amountCents).description)"))
            }
            if old.date != new.date { lines.append(String(localized: "Date: \(old.date.display) → \(new.date.display)")) }
            if old.paidBy != new.paidBy {
                lines.append(String(localized: "Paid by: \(context.name(of: old.paidBy)) → \(context.name(of: new.paidBy))"))
            }
            if old.split != new.split { lines.append(String(localized: "Split: \(describe(old.split)) → \(describe(new.split))")) }
            if old.hasServiceCharge != new.hasServiceCharge {
                lines.append(String(localized: "Service charge: \(yesNo(old.hasServiceCharge)) → \(yesNo(new.hasServiceCharge))"))
            }
            return lines
        case (.settlement(let old)?, .settlement(let new)) where change.action == "updated":
            var lines: [String] = []
            if old.amountCents != new.amountCents {
                lines.append(String(localized: "Amount: \(Money(cents: old.amountCents).description) → \(Money(cents: new.amountCents).description)"))
            }
            if old.fromMember != new.fromMember || old.toMember != new.toMember {
                lines.append(String(localized: "\(context.name(of: old.fromMember)) paid \(context.name(of: old.toMember)) → \(context.name(of: new.fromMember)) paid \(context.name(of: new.toMember))"))
            }
            if old.date != new.date { lines.append(String(localized: "Date: \(old.date.display) → \(new.date.display)")) }
            return lines
        case (nil, .expense(let new)):
            return [String(localized: "\(new.title), \(Money(cents: new.amountCents).description), paid by \(context.name(of: new.paidBy))")]
        case (nil, .settlement(let new)):
            return [String(localized: "\(context.name(of: new.fromMember)) paid \(context.name(of: new.toMember)) \(Money(cents: new.amountCents).description)")]
        default:
            return []
        }
    }

    private func describe(_ split: SplitRow) -> String {
        if split.isExact {
            let people = (split.amounts ?? [:]).sorted { $0.key < $1.key }.map {
                "\(UUID(uuidString: $0.key).map(context.name(of:)) ?? "?") \(Money(cents: $0.value).description)"
            }.formatted(.list(type: .and))
            return String(localized: "Exact amounts (\(people))")
        }
        let people = (split.members ?? []).map(context.name(of:)).formatted(.list(type: .and))
        return String(localized: "Equally (\(people))")
    }

    private func yesNo(_ value: Bool) -> String {
        value ? String(localized: "Yes") : String(localized: "No")
    }
}

/// A Member's initial in a coloured circle. The colour comes from their id, so it stays the same
/// everywhere and on every device. A Placeholder Member gets a dashed outline instead.
struct Avatar: View {
    let member: GroupMember
    var size: CGFloat = 36

    private static let palette: [(background: Color, foreground: Color)] = [
        (Color(red: 0.95, green: 0.78, blue: 0.70), Color(red: 0.48, green: 0.18, blue: 0.08)),
        (Color(red: 0.75, green: 0.89, blue: 0.85), Color(red: 0.05, green: 0.31, blue: 0.27)),
        (Color(red: 0.80, green: 0.84, blue: 0.97), Color(red: 0.15, green: 0.19, blue: 0.48)),
        (Color(red: 0.96, green: 0.88, blue: 0.64), Color(red: 0.42, green: 0.31, blue: 0.00)),
        (Color(red: 0.91, green: 0.78, blue: 0.93), Color(red: 0.36, green: 0.12, blue: 0.42)),
    ]

    var body: some View {
        let colors = Self.palette[Self.colorIndex(for: member.id)]
        Text(String(member.name.prefix(1)).uppercased())
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .frame(width: size, height: size)
            .foregroundStyle(member.userID == nil ? Color.secondary : colors.foreground)
            .background {
                if member.userID == nil {
                    Circle().strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                } else {
                    Circle().fill(colors.background)
                }
            }
            .accessibilityHidden(true)
    }

    private static func colorIndex(for id: UUID) -> Int {
        let bytes = withUnsafeBytes(of: id.uuid) { Array($0) }
        return bytes.reduce(0) { ($0 + Int($1)) % palette.count }
    }
}
