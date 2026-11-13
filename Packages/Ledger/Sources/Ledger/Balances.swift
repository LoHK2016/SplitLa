/// A payment the Ledger suggests to clear the Group's Balances.
public struct Transfer: Equatable, Sendable {
    public let from: MemberID
    public let to: MemberID
    public let amount: Money

    public init(from: MemberID, to: MemberID, amount: Money) {
        self.from = from
        self.to = to
        self.amount = amount
    }
}

extension GroupState {
    /// Each Member's Balance across every Activity in the Group. Positive means the
    /// Group owes them; negative means they owe the Group. Balances always sum to zero.
    public func balances() -> [MemberID: Money] {
        var result = Dictionary(uniqueKeysWithValues: members.map { ($0.id, Money.zero) })
        for expense in expenses where !expense.isDeleted {
            result[expense.paidBy, default: .zero] += expense.total
            for (member, share) in expense.shares {
                result[member, default: .zero] -= share
            }
        }
        for settlement in settlements where !settlement.isDeleted {
            result[settlement.from, default: .zero] += settlement.amount
            result[settlement.to, default: .zero] -= settlement.amount
        }
        return result
    }

    /// Transfers that bring every Balance to zero, pairing the largest debtor with the
    /// largest creditor each time. Never more than (members - 1) transfers.
    public func suggestedTransfers() -> [Transfer] {
        var open = balances().filter { $0.value != .zero }
        var transfers: [Transfer] = []
        while true {
            // Ties break on member ID so the suggestion is stable between devices.
            let debtor = open.filter { $0.value < .zero }
                .min { ($0.value, $0.key) < ($1.value, $1.key) }
            let creditor = open.filter { $0.value > .zero }
                .max { ($0.value, $1.key) < ($1.value, $0.key) }
            guard let debtor, let creditor else { break }
            let amount = min(-debtor.value, creditor.value)
            transfers.append(Transfer(from: debtor.key, to: creditor.key, amount: amount))
            open[debtor.key]! += amount
            open[creditor.key]! -= amount
            open = open.filter { $0.value != .zero }
        }
        return transfers
    }
}
