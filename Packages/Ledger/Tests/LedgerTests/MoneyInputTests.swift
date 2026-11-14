import Testing
@testable import Ledger

@Suite struct MoneyInput {
    @Test(arguments: [
        ("800", 80000), ("12.5", 1250), ("12.50", 1250), ("0.05", 5), (" 1,200 ", 120000),
        ("$88", 8800), ("0", 0), (".5", 50), ("7.", 700),
    ])
    func typedAmountBecomesExactCents(text: String, cents: Int) {
        #expect(Money(typed: text) == Money(cents: cents))
    }

    @Test(arguments: ["", "abc", "12.345", "-5", "1.2.3", "12a", "."])
    func anythingElseIsNotAnAmount(text: String) {
        #expect(Money(typed: text) == nil)
    }

    @Test func plainTextDropsTheDollarSignSoItCanBeTypedBackIn() {
        #expect(Money(cents: 1250).plain == "12.50")
        #expect(Money(dollars: 800).plain == "800")
        #expect(Money(typed: Money(cents: 99999).plain) == Money(cents: 99999))
    }
}
