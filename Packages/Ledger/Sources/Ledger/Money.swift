import Foundation

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

extension Money {
    /// Reads an amount as a person types it: dollars with up to two decimal places.
    /// A leading "$", commas and surrounding spaces are ignored. Nil for anything else,
    /// including negative amounts.
    public init?(typed text: String) {
        var cleaned = text.filter { !$0.isWhitespace && $0 != "," }
        if cleaned.hasPrefix("$") { cleaned.removeFirst() }
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2, parts.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } }) else { return nil }
        let whole = parts[0]
        let fraction = parts.count == 2 ? parts[1] : ""
        guard !(whole.isEmpty && fraction.isEmpty), fraction.count <= 2,
              let dollars = Int(whole.isEmpty ? "0" : whole)
        else { return nil }
        let padded = fraction + String(repeating: "0", count: 2 - fraction.count)
        self.init(cents: dollars * 100 + Int(padded)!)
    }

    /// The amount without the dollar sign, as it would be typed: "800" or "12.50".
    public var plain: String {
        let text = description.replacingOccurrences(of: "$", with: "")
        return text.hasSuffix(".00") ? String(text.dropLast(3)) : text
    }
}
