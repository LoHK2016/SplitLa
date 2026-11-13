import Testing
@testable import Ledger

@Suite struct ExpenseShares {
    @Test func equalSplitDividesEvenly() throws {
        let e = expense("e", dollars(300), paidBy: amy, among: [amy, ben, cat])
        #expect(e.shares == [amy: dollars(100), ben: dollars(100), cat: dollars(100)])
    }

    @Test func equalSplitGivesLeftoverCentsToFirstMembers() throws {
        let e = expense("e", dollars(100), paidBy: amy, among: [amy, ben, cat])
        #expect(e.shares == [amy: cents(3334), ben: cents(3333), cat: cents(3333)])
        #expect(e.shares.values.sum() == e.total)
    }

    @Test(arguments: [1, 7, 99, 100, 101, 12345, 99999], [1, 2, 3, 4, 5, 7])
    func equalSharesAlwaysSumToTotal(amount: Int, headcount: Int) throws {
        let people = Set([amy, ben, cat, dan, eve, "fay", "gus"].prefix(headcount))
        for serviceCharge in [false, true] {
            let e = expense("e", cents(amount), paidBy: amy, among: people, serviceCharge: serviceCharge)
            #expect(e.shares.values.sum() == e.total)
            #expect(e.shares.count == headcount)
        }
    }

    @Test func serviceChargeAddsTenPercentRoundedHalfUp() throws {
        #expect(dollars(800).withServiceCharge == dollars(880))
        #expect(cents(1005).withServiceCharge == cents(1106))  // 1105.5 rounds up
        #expect(cents(1004).withServiceCharge == cents(1104))  // 1104.4 rounds down
    }

    @Test func equalSplitWithServiceChargeSplitsTheChargedTotal() throws {
        let e = expense("e", dollars(100), paidBy: amy, among: [amy, ben, cat], serviceCharge: true)
        #expect(e.total == dollars(110))
        #expect(e.shares == [amy: cents(3667), ben: cents(3667), cat: cents(3666)])
    }

    @Test func exactSplitUsesEnteredAmounts() throws {
        let e = try Expense(
            id: "e", activityID: "dinner", title: "", date: day(2026, 12, 5), amount: dollars(500),
            paidBy: amy, split: .exact([amy: dollars(300), ben: dollars(200)])
        )
        #expect(e.shares == [amy: dollars(300), ben: dollars(200)])
    }

    @Test func exactSplitThatDoesNotAddUpReportsTheDifference() {
        #expect(throws: LedgerError.exactAmountsMismatch(difference: dollars(50))) {
            try Expense(
                id: "e", activityID: "dinner", title: "", date: day(2026, 12, 5), amount: dollars(500),
                paidBy: amy, split: .exact([amy: dollars(300), ben: dollars(150)])
            )
        }
    }

    @Test func exactSplitWithServiceChargeStillSumsToTotal() throws {
        // Each share rounds up on its own (3 x 36.67 = 110.01) but the bill is 110.00.
        let third = cents(3335)
        let e = try Expense(
            id: "e", activityID: "dinner", title: "", date: day(2026, 12, 5), amount: cents(10005),
            paidBy: amy, split: .exact([amy: third, ben: third, cat: third]), hasServiceCharge: true
        )
        #expect(e.total == cents(11006))
        #expect(e.shares.values.sum() == e.total)
        #expect(e.shares == [amy: cents(3668), ben: cents(3669), cat: cents(3669)])
    }

    @Test func expenseNeedsSomeoneToShareIt() {
        #expect(throws: LedgerError.noParticipants) {
            try Expense(
                id: "e", activityID: "dinner", title: "", date: day(2026, 12, 5), amount: dollars(1),
                paidBy: amy, split: .equal(among: [])
            )
        }
    }
}
