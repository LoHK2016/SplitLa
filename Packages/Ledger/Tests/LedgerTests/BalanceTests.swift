import Testing
@testable import Ledger

@Suite struct Balances {
    @Test func payerIsOwedEveryoneElsesShare() {
        let group = GroupState(
            members: members(amy, ben, cat),
            expenses: [expense("e", dollars(300), paidBy: amy, among: [amy, ben, cat])]
        )
        #expect(group.balances() == [amy: dollars(200), ben: dollars(-100), cat: dollars(-100)])
    }

    @Test func balanceRunsAcrossActivities() {
        let group = GroupState(
            members: members(amy, ben),
            expenses: [
                expense("e1", in: "dinner", dollars(200), paidBy: amy, among: [amy, ben]),
                expense("e2", in: "trip", dollars(60), paidBy: ben, among: [amy, ben]),
            ]
        )
        #expect(group.balances() == [amy: dollars(70), ben: dollars(-70)])
    }

    @Test func deletedExpensesDoNotCount() {
        var deleted = expense("e", dollars(300), paidBy: amy, among: [amy, ben])
        deleted.isDeleted = true
        let group = GroupState(members: members(amy, ben), expenses: [deleted])
        #expect(group.balances() == [amy: .zero, ben: .zero])
    }

    @Test func settlementMovesBothBalancesTowardsZero() {
        let group = GroupState(
            members: members(amy, ben),
            expenses: [expense("e", dollars(200), paidBy: amy, among: [amy, ben])],
            settlements: [Settlement(id: "s", from: ben, to: amy, amount: dollars(60), date: day(2026, 12, 6))]
        )
        #expect(group.balances() == [amy: dollars(40), ben: dollars(-40)])
    }

    @Test func deletedSettlementsDoNotCount() {
        let group = GroupState(
            members: members(amy, ben),
            expenses: [expense("e", dollars(200), paidBy: amy, among: [amy, ben])],
            settlements: [Settlement(id: "s", from: ben, to: amy, amount: dollars(60), date: day(2026, 12, 6), isDeleted: true)]
        )
        #expect(group.balances() == [amy: dollars(100), ben: dollars(-100)])
    }

    @Test func balancesAlwaysSumToZero() {
        #expect(messyGroup.balances().values.sum() == .zero)
    }

    @Test func chainOfDebtsCollapsesIntoOneTransfer() {
        // Amy owes Ben 100 and Ben owes Cat 100, so Amy should simply pay Cat.
        let group = GroupState(
            members: members(amy, ben, cat),
            expenses: [
                try! Expense(id: "e1", activityID: "a", title: "", date: day(2026, 12, 1), amount: dollars(100),
                             paidBy: ben, split: .exact([amy: dollars(100)])),
                try! Expense(id: "e2", activityID: "a", title: "", date: day(2026, 12, 1), amount: dollars(100),
                             paidBy: cat, split: .exact([ben: dollars(100)])),
            ]
        )
        #expect(group.suggestedTransfers() == [Transfer(from: amy, to: cat, amount: dollars(100))])
    }

    @Test func followingTheSuggestedTransfersClearsEveryBalance() {
        var group = messyGroup
        let transfers = group.suggestedTransfers()
        #expect(transfers.count <= group.members.count - 1)
        #expect(transfers.allSatisfy { $0.amount > .zero })
        for (index, transfer) in transfers.enumerated() {
            group.settlements.append(Settlement(
                id: SettlementID("pay\(index)"), from: transfer.from, to: transfer.to,
                amount: transfer.amount, date: day(2026, 12, 31)
            ))
        }
        #expect(group.balances().values.allSatisfy { $0 == .zero })
        #expect(group.suggestedTransfers().isEmpty)
    }

    @Test func settledGroupHasNothingToTransfer() {
        #expect(GroupState(members: members(amy, ben)).suggestedTransfers().isEmpty)
    }

    @Test func claimingAPlaceholderLeavesTheAccountsAlone() throws {
        var group = messyGroup
        group.members.append(Member(id: "fay", name: "Fay", isPlaceholder: true))
        group.expenses.append(expense("e9", dollars(90), paidBy: amy, among: [amy, "fay"]))
        let before = group.balances()

        try group.claimPlaceholder("fay")

        #expect(group.balances() == before)
        #expect(group.members.first { $0.id == "fay" }?.isPlaceholder == false)
        #expect(throws: LedgerError.notAPlaceholder) { try group.claimPlaceholder("fay") }
    }

    @Test func leavingTurnsAMemberIntoAPlaceholderAndKeepsTheirBalance() throws {
        var group = messyGroup
        let before = group.balances()
        #expect(before[ben] != .zero)

        try group.leave(ben)

        #expect(group.balances() == before)
        #expect(group.members.first { $0.id == ben }?.isPlaceholder == true)
        #expect(throws: LedgerError.alreadyAPlaceholder) { try group.leave(ben) }
    }
}

/// Five people, uneven expenses with awkward cents, a service charge and a part settlement.
let messyGroup = GroupState(
    members: members(amy, ben, cat, dan, eve),
    expenses: [
        expense("e1", cents(100_01), paidBy: amy, among: [amy, ben, cat]),
        expense("e2", cents(47_35), paidBy: ben, among: [amy, ben, cat, dan, eve], serviceCharge: true),
        expense("e3", cents(999_99), paidBy: cat, among: [dan, eve]),
        expense("e4", cents(12_50), paidBy: eve, among: [amy, eve]),
    ],
    settlements: [Settlement(id: "s1", from: dan, to: cat, amount: dollars(120), date: day(2026, 12, 9))]
)
