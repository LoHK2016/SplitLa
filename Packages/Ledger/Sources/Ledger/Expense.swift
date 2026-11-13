import Foundation

/// How an Expense is divided into Shares.
public enum Split: Equatable, Sendable {
    /// Everyone listed carries the same Share.
    case equal(among: Set<MemberID>)
    /// Each member carries the amount entered for them, before any service charge.
    case exact([MemberID: Money])
}

/// Money already spent within an Activity. An Expense is always valid once built:
/// its Shares sum to its total.
public struct Expense: Identifiable, Equatable, Sendable {
    public let id: ExpenseID
    public let activityID: ActivityID
    public let title: String
    public let date: Date
    /// The amount as entered, before the service charge.
    public let amount: Money
    public let paidBy: MemberID
    public let split: Split
    public let hasServiceCharge: Bool
    public var isDeleted: Bool
    /// What each member carries, service charge included. Sums to `total`.
    public let shares: [MemberID: Money]

    /// What was actually paid, service charge included.
    public var total: Money { hasServiceCharge ? amount.withServiceCharge : amount }

    public init(
        id: ExpenseID, activityID: ActivityID, title: String, date: Date, amount: Money,
        paidBy: MemberID, split: Split, hasServiceCharge: Bool = false, isDeleted: Bool = false
    ) throws {
        self.id = id
        self.activityID = activityID
        self.title = title
        self.date = date
        self.amount = amount
        self.paidBy = paidBy
        self.split = split
        self.hasServiceCharge = hasServiceCharge
        self.isDeleted = isDeleted
        self.shares = try Self.computeShares(amount: amount, split: split, hasServiceCharge: hasServiceCharge)
    }

    private static func computeShares(
        amount: Money, split: Split, hasServiceCharge: Bool
    ) throws -> [MemberID: Money] {
        guard amount >= .zero else { throw LedgerError.negativeAmount }
        let total = hasServiceCharge ? amount.withServiceCharge : amount

        switch split {
        case .equal(let members):
            guard !members.isEmpty else { throw LedgerError.noParticipants }
            let order = members.sorted()
            return Dictionary(uniqueKeysWithValues: zip(order, total.splitEvenly(into: order.count)))

        case .exact(let amounts):
            guard !amounts.isEmpty else { throw LedgerError.noParticipants }
            guard amounts.values.allSatisfy({ $0 >= .zero }) else { throw LedgerError.negativeAmount }
            let difference = amount - amounts.values.sum()
            guard difference == .zero else { throw LedgerError.exactAmountsMismatch(difference: difference) }
            guard hasServiceCharge else { return amounts }

            // Each Share takes the service charge on its own, then the cents lost or gained
            // by rounding are settled one each on the first members so Shares sum to the total.
            let order = amounts.keys.sorted()
            var shares = amounts.mapValues(\.withServiceCharge)
            var drift = (total - shares.values.sum()).cents
            var index = 0
            while drift != 0 {
                let step = drift > 0 ? 1 : -1
                let member = order[index % order.count]
                if shares[member]!.cents + step >= 0 {
                    shares[member]!.cents += step
                    drift -= step
                }
                index += 1
            }
            return shares
        }
    }
}
