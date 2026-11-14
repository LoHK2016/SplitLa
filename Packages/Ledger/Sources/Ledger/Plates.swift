/// A meal priced by the plate, as at a conveyor-belt sushi restaurant: each kind of plate has
/// its own price, and each person pays for the plates they took.
///
/// The result is an exact amount for each person, so the Expense it becomes is an ordinary
/// exact-amounts Expense: `Split.exact(tally.amounts)` for `tally.total`.
public struct PlateTally: Equatable, Sendable {
    /// The price of each kind of plate, in the order they are shown.
    public var prices: [Money]
    /// How many plates of each price each member took. Positions match `prices`; a missing
    /// position counts as none.
    public private(set) var counts: [MemberID: [Int]]

    public init(prices: [Money], counts: [MemberID: [Int]] = [:]) {
        self.prices = prices
        self.counts = counts
    }

    public func count(of member: MemberID, priceAt index: Int) -> Int {
        guard let plates = counts[member], plates.indices.contains(index) else { return 0 }
        return plates[index]
    }

    /// Adds plates (or takes them away, with a negative number). Never goes below none.
    public mutating func add(_ plates: Int, to member: MemberID, priceAt index: Int) {
        guard prices.indices.contains(index) else { return }
        var row = counts[member] ?? []
        if row.count < prices.count { row += Array(repeating: 0, count: prices.count - row.count) }
        row[index] = max(0, row[index] + plates)
        counts[member] = row
    }

    /// Drops a kind of plate, along with everyone's plates of that kind.
    public mutating func removePrice(at index: Int) {
        guard prices.indices.contains(index) else { return }
        prices.remove(at: index)
        for member in counts.keys where counts[member]!.indices.contains(index) {
            counts[member]!.remove(at: index)
        }
    }

    /// What each member's plates come to, before any service charge. Members with no plates
    /// are left out, so they carry no Share.
    public var amounts: [MemberID: Money] {
        var result: [MemberID: Money] = [:]
        for member in counts.keys {
            let amount = prices.indices.map { prices[$0] * count(of: member, priceAt: $0) }.sum()
            if amount > .zero { result[member] = amount }
        }
        return result
    }

    /// Every plate together, before any service charge.
    public var total: Money { amounts.values.sum() }
}
