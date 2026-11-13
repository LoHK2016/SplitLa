import Foundation

/// A typed identifier. The tag stops a MemberID being passed where an ActivityID is expected.
public struct ID<Tag>: Hashable, Comparable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { self.rawValue = value }
    public static func < (a: ID, b: ID) -> Bool { a.rawValue < b.rawValue }
    public var description: String { rawValue }
}

public enum MemberTag {}
public enum ActivityTag {}
public enum ExpenseTag {}
public enum ProposalTag {}
public enum SettlementTag {}

public typealias MemberID = ID<MemberTag>
public typealias ActivityID = ID<ActivityTag>
public typealias ExpenseID = ID<ExpenseTag>
public typealias ProposalID = ID<ProposalTag>
public typealias SettlementID = ID<SettlementTag>

/// A person in a Group. A Placeholder Member has no account behind it but is
/// identical to any other Member as far as the money is concerned.
public struct Member: Identifiable, Equatable, Sendable {
    public let id: MemberID
    public var name: String
    public var isPlaceholder: Bool

    public init(id: MemberID, name: String, isPlaceholder: Bool = false) {
        self.id = id
        self.name = name
        self.isPlaceholder = isPlaceholder
    }
}

public enum Attendance: Equatable, Sendable {
    case going, notGoing, noReply
}

public struct Activity: Identifiable, Equatable, Sendable {
    public let id: ActivityID
    public var name: String
    public var date: Date?
    public var organiser: MemberID
    /// The Activity Budget. Optional; visible to the whole Group.
    public var budget: Money?
    /// Members missing from this dictionary have not replied.
    public var attendance: [MemberID: Attendance]

    public init(
        id: ActivityID, name: String, date: Date? = nil, organiser: MemberID,
        budget: Money? = nil, attendance: [MemberID: Attendance] = [:]
    ) {
        self.id = id
        self.name = name
        self.date = date
        self.organiser = organiser
        self.budget = budget
        self.attendance = attendance
    }

    public func attendance(of member: MemberID) -> Attendance { attendance[member] ?? .noReply }

    /// Members who replied "going", in the fixed order used for handing out leftover cents.
    public var goingMembers: [MemberID] {
        attendance.filter { $0.value == .going }.keys.sorted()
    }
}

public struct Settlement: Identifiable, Equatable, Sendable {
    public let id: SettlementID
    public var from: MemberID
    public var to: MemberID
    public var amount: Money
    public var date: Date
    public var isDeleted: Bool

    public init(id: SettlementID, from: MemberID, to: MemberID, amount: Money, date: Date, isDeleted: Bool = false) {
        self.id = id
        self.from = from
        self.to = to
        self.amount = amount
        self.date = date
        self.isDeleted = isDeleted
    }
}

/// Everything the Ledger needs to know about one Group.
public struct GroupState: Equatable, Sendable {
    public var members: [Member]
    public var activities: [Activity]
    public var expenses: [Expense]
    public var proposals: [Proposal]
    public var settlements: [Settlement]

    public init(
        members: [Member] = [], activities: [Activity] = [], expenses: [Expense] = [],
        proposals: [Proposal] = [], settlements: [Settlement] = []
    ) {
        self.members = members
        self.activities = activities
        self.expenses = expenses
        self.proposals = proposals
        self.settlements = settlements
    }

    public func activity(_ id: ActivityID) -> Activity? { activities.first { $0.id == id } }
    public func proposal(_ id: ProposalID) -> Proposal? { proposals.first { $0.id == id } }
}

public enum LedgerError: Error, Equatable, Sendable {
    case noParticipants
    case negativeAmount
    /// Exact amounts do not add up to the Expense amount. `difference` is amount minus the sum.
    case exactAmountsMismatch(difference: Money)
    case proposalNotFound
    case activityNotFound
    case memberNotFound
    case notOrganiser
    case activityHasNoDate
    case proposalNotOpenOrChosen
    case proposalNotChosen
    case notAPlaceholder
    case alreadyAPlaceholder
}

/// A calendar month, the period a Personal Budget covers.
public struct YearMonth: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    public init(_ date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.year = parts.year!
        self.month = parts.month!
    }

    public static func < (a: YearMonth, b: YearMonth) -> Bool { (a.year, a.month) < (b.year, b.month) }
    public var description: String { "\(year)-\(month < 10 ? "0" : "")\(month)" }
}
