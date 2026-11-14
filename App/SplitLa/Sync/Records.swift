import Foundation
import Ledger

/// A calendar day with no time of day, as the server stores Activity and Expense dates.
struct Day: Codable, Hashable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        (year, month, day) = (parts.year!, parts.month!, parts.day!)
    }

    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a day: \(text)"))
        }
        (year, month, day) = (parts[0], parts[1], parts[2])
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    /// "2026-12-05", the form the server takes.
    var text: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Midday on this day, so it lands in the same calendar month in any nearby time zone.
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}

// Rows as the server returns them. Property names follow the columns (snake_case becomes camelCase).

struct ActivityRow: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupId: UUID
    var name: String
    var date: Day?
    let organiserId: UUID
    var budgetCents: Int?
}

/// Who shares an Expense, as stored: either a list of Members, or an amount for each.
struct SplitRow: Codable, Hashable, Sendable {
    var kind: String
    var members: [UUID]?
    /// Member id (lowercase) to cents.
    var amounts: [String: Int]?

    static func equal(_ members: [UUID]) -> SplitRow {
        SplitRow(kind: "equal", members: members.sorted { $0.uuidString < $1.uuidString }, amounts: nil)
    }

    static func exact(_ amounts: [UUID: Money]) -> SplitRow {
        SplitRow(
            kind: "exact", members: nil,
            amounts: Dictionary(uniqueKeysWithValues: amounts.map { ($0.key.uuidString.lowercased(), $0.value.cents) }))
    }

    var isExact: Bool { kind == "exact" }

    /// Everyone who shares the Expense.
    var participants: [UUID] {
        isExact ? (amounts ?? [:]).keys.compactMap(UUID.init(uuidString:)) : members ?? []
    }

    var ledger: Split {
        if isExact {
            .exact(Dictionary(uniqueKeysWithValues: (amounts ?? [:]).map {
                (MemberID($0.key.lowercased()), Money(cents: $0.value))
            }))
        } else {
            .equal(among: Set((members ?? []).map(\.memberID)))
        }
    }
}

/// The plates behind an Expense split by plates: each kind of plate, and how many each Member took.
/// The money comes from the exact amounts; the server checks these agree with them.
struct PlatesRow: Codable, Hashable, Sendable {
    struct PlateKind: Codable, Hashable, Sendable {
        var kind: String
        var name: String
        var priceCents: Int
        var colorIndex: Int
    }

    var types: [PlateKind]
    /// Member id (lowercase) to the number of plates of each kind, in the order of `types`.
    var counts: [String: [Int]]
}

struct ExpenseRow: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupId: UUID
    let activityId: UUID
    var proposalId: UUID?
    var title: String
    var date: Day
    var amountCents: Int
    var paidBy: UUID
    var split: SplitRow
    var hasServiceCharge: Bool
    var plates: PlatesRow?
    var deletedAt: String?

    var isDeleted: Bool { deletedAt != nil }

    /// Nil if the row breaks a Ledger rule, which the server should never allow.
    var ledger: Expense? {
        try? Expense(
            id: ExpenseID(id.uuidString.lowercased()), activityID: ActivityID(activityId.uuidString.lowercased()),
            title: title, date: date.date(), amount: Money(cents: amountCents), paidBy: paidBy.memberID,
            split: split.ledger, hasServiceCharge: hasServiceCharge, isDeleted: isDeleted)
    }
}

struct SettlementRow: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupId: UUID
    var fromMember: UUID
    var toMember: UUID
    var amountCents: Int
    var date: Day
    var deletedAt: String?

    var isDeleted: Bool { deletedAt != nil }
}

struct AttendanceRow: Codable, Hashable, Sendable {
    let activityId: UUID
    let memberId: UUID
    var status: String

    var ledger: Attendance {
        switch status {
        case "going": .going
        case "not_going": .notGoing
        default: .noReply
        }
    }
}

extension Attendance {
    var serverValue: String {
        switch self {
        case .going: "going"
        case .notGoing: "not_going"
        case .noReply: "no_reply"
        }
    }
}

struct ProposalRow: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let groupId: UUID
    let activityId: UUID
    var title: String
    var amountKind: String
    var amountCents: Int
    var status: String

    var proposalID: ProposalID { ProposalID(id.uuidString.lowercased()) }

    var ledger: Proposal {
        let amount = Money(cents: amountCents)
        let status: ProposalStatus = switch status {
        case "chosen": .chosen
        case "converted": .converted
        default: .open
        }
        return Proposal(
            id: proposalID, activityID: ActivityID(activityId.uuidString.lowercased()), title: title,
            amount: amountKind == "per_person" ? .perPerson(amount) : .total(amount), status: status)
    }
}

/// One entry in the history of an Expense or Settlement.
struct ChangeRow: Decodable, Identifiable, Sendable {
    enum Snapshot: Sendable {
        case expense(ExpenseRow)
        case settlement(SettlementRow)
    }

    let id: Int
    let action: String
    let actorName: String
    let at: Date
    let before: Snapshot?
    let after: Snapshot

    enum CodingKeys: String, CodingKey { case id, entity, action, actorName, at, before, after }

    init(from decoder: any Decoder) throws {
        let row = try decoder.container(keyedBy: CodingKeys.self)
        id = try row.decode(Int.self, forKey: .id)
        action = try row.decode(String.self, forKey: .action)
        actorName = try row.decode(String.self, forKey: .actorName)
        at = try row.decode(Date.self, forKey: .at)
        if try row.decode(String.self, forKey: .entity) == "settlement" {
            before = try row.decodeIfPresent(SettlementRow.self, forKey: .before).map(Snapshot.settlement)
            after = .settlement(try row.decode(SettlementRow.self, forKey: .after))
        } else {
            before = try row.decodeIfPresent(ExpenseRow.self, forKey: .before).map(Snapshot.expense)
            after = .expense(try row.decode(ExpenseRow.self, forKey: .after))
        }
    }
}

/// Everything the app holds about one Group: what was last read from the server.
struct GroupSnapshot: Codable, Sendable {
    var group: GroupSummary
    var members: [GroupMember]
    var activities: [ActivityRow]
    var attendance: [AttendanceRow]
    var expenses: [ExpenseRow]
    var proposals: [ProposalRow]
    var settlements: [SettlementRow]

    /// The same Group in the form the Ledger does its sums on.
    var ledger: GroupState {
        let replies = Dictionary(grouping: attendance, by: \.activityId)
        return GroupState(
            members: members.map { Member(id: $0.id.memberID, name: $0.name, isPlaceholder: $0.userID == nil) },
            activities: activities.map { activity in
                Activity(
                    id: ActivityID(activity.id.uuidString.lowercased()), name: activity.name,
                    date: activity.date?.date(), organiser: activity.organiserId.memberID,
                    budget: activity.budgetCents.map(Money.init(cents:)),
                    attendance: Dictionary(
                        (replies[activity.id] ?? []).map { ($0.memberId.memberID, $0.ledger) },
                        uniquingKeysWith: { $1 }))
            },
            expenses: expenses.compactMap(\.ledger),
            proposals: proposals.map(\.ledger),
            settlements: settlements.map {
                Settlement(
                    id: SettlementID($0.id.uuidString.lowercased()), from: $0.fromMember.memberID,
                    to: $0.toMember.memberID, amount: Money(cents: $0.amountCents), date: $0.date.date(),
                    isDeleted: $0.isDeleted)
            })
    }
}

extension UUID {
    /// The Ledger's name for the Member with this id.
    var memberID: MemberID { MemberID(uuidString.lowercased()) }
}

extension MemberID {
    var uuid: UUID? { UUID(uuidString: rawValue) }
}
