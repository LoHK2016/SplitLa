/// An amount of Hong Kong dollars held as whole cents, so arithmetic is exact.
/// Negative amounts are allowed: a Balance or a remaining budget can be below zero.
public struct Money: Hashable, Comparable, Sendable, AdditiveArithmetic, CustomStringConvertible {
    public var cents: Int

    public init(cents: Int) { self.cents = cents }

    /// Whole dollars, e.g. `Money(dollars: 800)` is $800.00.
    public init(dollars: Int) { self.cents = dollars * 100 }

    public static let zero = Money(cents: 0)

    public static func + (a: Money, b: Money) -> Money { Money(cents: a.cents + b.cents) }
    public static func - (a: Money, b: Money) -> Money { Money(cents: a.cents - b.cents) }
    public static prefix func - (a: Money) -> Money { Money(cents: -a.cents) }
    public static func * (a: Money, n: Int) -> Money { Money(cents: a.cents * n) }
    public static func < (a: Money, b: Money) -> Bool { a.cents < b.cents }

    /// The amount with the 10% service charge added, rounded half up to the cent.
    public var withServiceCharge: Money {
        precondition(cents >= 0, "service charge applies to non-negative amounts")
        return Money(cents: (cents * 11 + 5) / 10)
    }

    /// Splits a non-negative amount into `count` parts that always sum to the amount.
    /// When it does not divide evenly, the leftover cents go one each to the first parts.
    public func splitEvenly(into count: Int) -> [Money] {
        precondition(count > 0 && cents >= 0)
        let base = cents / count
        let leftover = cents % count
        return (0..<count).map { Money(cents: base + ($0 < leftover ? 1 : 0)) }
    }

    public var description: String {
        let sign = cents < 0 ? "-" : ""
        let abs = Swift.abs(cents)
        let fraction = abs % 100
        return "\(sign)$\(abs / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}

extension Sequence where Element == Money {
    public func sum() -> Money { reduce(.zero, +) }
}
