import Testing
@testable import Ledger

@Suite struct Proposals {
    let dinner = Activity(
        id: "dinner", name: "聖誕大餐", date: day(2026, 12, 24), organiser: amy,
        attendance: [amy: .going, ben: .going, cat: .going, dan: .notGoing]
    )

    func group(_ proposals: Proposal..., activity: Activity? = nil) -> GroupState {
        GroupState(members: members(amy, ben, cat, dan, eve), activities: [activity ?? dinner], proposals: proposals)
    }

    @Test func perPersonProposalCostsEachPersonTheSame() {
        let g = group(Proposal(id: "p", activityID: "dinner", title: "餐廳 A", amount: .perPerson(dollars(800))))
        #expect(g.share(of: "p", for: amy) == dollars(800))
        #expect(g.total(of: "p") == dollars(2400))
    }

    @Test func totalProposalIsSharedByThoseGoing() {
        let g = group(Proposal(id: "p", activityID: "dinner", title: "包場", amount: .total(dollars(4000))))
        #expect(g.total(of: "p") == dollars(4000))
        #expect(g.share(of: "p", for: amy) == cents(1333_34))
        #expect(g.share(of: "p", for: ben) == cents(1333_33))
    }

    @Test func someoneNotGoingSeesTheirShareAsIfTheyWent() {
        let g = group(Proposal(id: "p", activityID: "dinner", title: "包場", amount: .total(dollars(4000))))
        #expect(g.share(of: "p", for: dan) == dollars(1000))  // said no
        #expect(g.share(of: "p", for: eve) == dollars(1000))  // has not replied
    }

    @Test func sharesRiseWhenPeopleDropOut() {
        var activity = dinner
        activity.attendance = going(amy, ben, cat, dan, eve)
        var g = group(Proposal(id: "p", activityID: "dinner", title: "包場", amount: .total(dollars(4000))), activity: activity)
        #expect(g.share(of: "p", for: amy) == dollars(800))

        g.activities[0].attendance[dan] = .notGoing
        g.activities[0].attendance[eve] = .notGoing
        #expect(g.share(of: "p", for: amy) == cents(1333_34))
    }

    @Test func onlyTheOrganiserCanChoose() {
        var g = group(Proposal(id: "p", activityID: "dinner", title: "A", amount: .perPerson(dollars(800))))
        #expect(throws: LedgerError.notOrganiser) { try g.choose("p", by: ben) }
        #expect(g.proposal("p")?.status == .open)
    }

    @Test func choosingReplacesThePreviousChoice() throws {
        var g = group(
            Proposal(id: "a", activityID: "dinner", title: "A", amount: .perPerson(dollars(800))),
            Proposal(id: "b", activityID: "dinner", title: "B", amount: .perPerson(dollars(300)))
        )
        try g.choose("a", by: amy)
        try g.choose("b", by: amy)
        #expect(g.proposal("a")?.status == .open)
        #expect(g.proposal("b")?.status == .chosen)
    }

    @Test func organiserCanCancelTheChoice() throws {
        var g = group(Proposal(id: "p", activityID: "dinner", title: "A", amount: .perPerson(dollars(800))))
        try g.choose("p", by: amy)
        try g.unchoose("p", by: amy)
        #expect(g.proposal("p")?.status == .open)
        #expect(throws: LedgerError.proposalNotChosen) { try g.unchoose("p", by: amy) }
    }

    @Test func activityWithoutADateCannotHaveAChosenProposal() {
        var undated = dinner
        undated.date = nil
        var g = group(Proposal(id: "p", activityID: "dinner", title: "A", amount: .perPerson(dollars(800))), activity: undated)
        #expect(throws: LedgerError.activityHasNoDate) { try g.choose("p", by: amy) }
    }

    @Test func draftExpenseIsPrefilledFromTheChosenProposal() throws {
        var g = group(Proposal(id: "p", activityID: "dinner", title: "餐廳 A", amount: .perPerson(dollars(800))))
        #expect(throws: LedgerError.proposalNotChosen) { try g.expenseDraft(for: "p") }
        try g.choose("p", by: amy)
        let draft = try g.expenseDraft(for: "p")
        #expect(draft == ExpenseDraft(activityID: "dinner", title: "餐廳 A", amount: dollars(2400), participants: [amy, ben, cat]))
    }

    @Test func convertingRecordsTheExpenseAndRetiresTheProposal() throws {
        var g = group(Proposal(id: "p", activityID: "dinner", title: "餐廳 A", amount: .perPerson(dollars(800))))
        try g.choose("p", by: amy)
        let actual = expense("bill", on: day(2026, 12, 24), dollars(2550), paidBy: ben, among: [amy, ben, cat])

        try g.convert("p", into: actual)

        #expect(g.proposal("p")?.status == .converted)
        #expect(g.expenses == [actual])
        #expect(throws: LedgerError.proposalNotChosen) { try g.convert("p", into: actual) }
        #expect(throws: LedgerError.proposalNotOpenOrChosen) { try g.choose("p", by: amy) }
    }
}
