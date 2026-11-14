import Testing
@testable import Ledger

@Suite struct PlateTallies {
    /// Three prices of plate, like a conveyor-belt sushi place.
    let prices = [dollars(12), dollars(17), dollars(22)]

    @Test func eachPersonPaysForThePlatesTheyTook() {
        let tally = PlateTally(prices: prices, counts: [amy: [3, 1, 0], ben: [0, 2, 1]])
        #expect(tally.amounts == [amy: dollars(53), ben: dollars(56)])
        #expect(tally.total == dollars(109))
    }

    @Test func someoneWithNoPlatesHasNoShare() {
        let tally = PlateTally(prices: prices, counts: [amy: [2, 0, 0], ben: [0, 0, 0]])
        #expect(tally.amounts == [amy: dollars(24)])
    }

    @Test func addingAndTakingAwayPlatesNeverGoesBelowZero() {
        var tally = PlateTally(prices: prices)
        tally.add(2, to: cat, priceAt: 1)
        tally.add(-5, to: cat, priceAt: 1)
        tally.add(1, to: cat, priceAt: 2)
        #expect(tally.count(of: cat, priceAt: 1) == 0)
        #expect(tally.count(of: cat, priceAt: 2) == 1)
        #expect(tally.amounts == [cat: dollars(22)])
    }

    @Test func aPriceAddedLaterStartsAtNoPlatesForEveryone() {
        var tally = PlateTally(prices: prices, counts: [amy: [1, 0, 0]])
        tally.prices.append(dollars(27))
        #expect(tally.count(of: amy, priceAt: 3) == 0)
        tally.add(1, to: amy, priceAt: 3)
        #expect(tally.amounts == [amy: dollars(39)])
    }

    @Test func removingAPriceKeepsEveryoneElsesPlatesInPlace() {
        var tally = PlateTally(prices: prices, counts: [amy: [1, 2, 3], ben: [4]])
        tally.removePrice(at: 1)
        #expect(tally.prices == [dollars(12), dollars(22)])
        #expect(tally.count(of: amy, priceAt: 0) == 1)
        #expect(tally.count(of: amy, priceAt: 1) == 3)
        #expect(tally.count(of: ben, priceAt: 0) == 4)
        #expect(tally.amounts == [amy: dollars(78), ben: dollars(48)])
    }

    @Test func theExpenseFromATallySumsToTheChargedTotal() throws {
        let tally = PlateTally(prices: prices, counts: [amy: [3, 1, 0], ben: [0, 2, 1], cat: [1, 0, 0]])
        let expense = try Expense(
            id: "sushi", activityID: "dinner", title: "Sushi", date: day(2026, 12, 5),
            amount: tally.total, paidBy: amy, split: .exact(tally.amounts), hasServiceCharge: true)
        #expect(expense.total == dollars(121).withServiceCharge)
        #expect(expense.shares.values.sum() == expense.total)
        #expect(expense.shares[ben] == dollars(56).withServiceCharge)
    }
}
