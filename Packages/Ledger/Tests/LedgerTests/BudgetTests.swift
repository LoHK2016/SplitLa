import Testing
import Foundation
@testable import Ledger

@Suite struct ActivityBudgetCheck {
    func group(budget: Money?) -> GroupState {
        GroupState(
            members: members(amy, ben, cat),
            activities: [Activity(id: "dinner", name: "聖誕大餐", date: day(2026, 12, 24), organiser: amy,
                                  budget: budget, attendance: going(amy, ben, cat))],
            expenses: [expense("deposit", dollars(300), paidBy: amy, among: [amy, ben, cat])],
            proposals: [
                Proposal(id: "pricey", activityID: "dinner", title: "A", amount: .perPerson(dollars(800))),
                Proposal(id: "cheap", activityID: "dinner", title: "B", amount: .total(dollars(900))),
            ]
        )
    }

    @Test func proposalOverTheActivityBudgetIsFlaggedWithTheOverage() throws {
        let check = try #require(group(budget: dollars(2000)).activityCheck(for: "pricey"))
        #expect(check.spent == dollars(300))
        #expect(check.proposalTotal == dollars(2400))
        #expect(check.isOver)
        #expect(check.remaining == dollars(-700))
    }

    @Test func proposalWithinTheActivityBudgetShowsWhatIsLeft() throws {
        // Only this proposal and recorded expenses count: the pricey proposal is ignored.
        let check = try #require(group(budget: dollars(2000)).activityCheck(for: "cheap"))
        #expect(!check.isOver)
        #expect(check.remaining == dollars(800))
    }

    @Test func noActivityBudgetMeansNoActivityCheck() {
        #expect(group(budget: nil).activityCheck(for: "pricey") == nil)
    }
}

@Suite struct CommittedSpendAndPersonalCheck {
    let december = YearMonth(year: 2026, month: 12)
    let january = YearMonth(year: 2027, month: 1)

    /// Amy's December: a $200 share already spent, plus a chosen $500 dinner she is going to.
    var friends: GroupState {
        GroupState(
            members: members(amy, ben, cat),
            activities: [
                Activity(id: "hotpot", name: "打邊爐", date: day(2026, 12, 5), organiser: ben, attendance: going(amy, ben)),
                Activity(id: "xmas", name: "聖誕大餐", date: day(2026, 12, 24), organiser: ben, attendance: going(amy, ben, cat)),
            ],
            expenses: [expense("hotpot bill", in: "hotpot", on: day(2026, 12, 5), dollars(400), paidBy: ben, among: [amy, ben])],
            proposals: [
                Proposal(id: "bistro", activityID: "xmas", title: "小館", amount: .perPerson(dollars(500)), status: .chosen),
                Proposal(id: "omakase", activityID: "xmas", title: "廚師發辦", amount: .perPerson(dollars(1500))),
            ]
        )
    }

    let me = MemberIdentity(memberIDs: [amy, "amy@work"])

    @Test func committedSpendIsSharesSpentPlusChosenProposalsIAmGoingTo() {
        let spend = friends.committedSpend(for: amy, in: december, calendar: hongKong)
        #expect(spend.total == dollars(700))
        #expect(spend.items.map(\.source) == [.expense("hotpot bill"), .chosenProposal("bistro")])
    }

    @Test func myShareCountsNotWhatIPaid() {
        // Ben paid the whole $400 hotpot bill but only $200 of it is his.
        #expect(friends.committedSpend(for: ben, in: december, calendar: hongKong).total == dollars(700))
    }

    @Test func chosenProposalDoesNotCountUnlessIAmGoing() {
        var g = friends
        g.activities[1].attendance[amy] = .noReply
        #expect(g.committedSpend(for: amy, in: december, calendar: hongKong).total == dollars(200))
        g.activities[1].attendance[amy] = .notGoing
        #expect(g.committedSpend(for: amy, in: december, calendar: hongKong).total == dollars(200))
    }

    @Test func openProposalsDoNotCount() {
        var g = friends
        g.proposals[0].status = .open
        #expect(g.committedSpend(for: amy, in: december, calendar: hongKong).total == dollars(200))
    }

    @Test func convertingReplacesTheEstimateWithTheRealShare() throws {
        var g = friends
        let bill = expense("xmas bill", in: "xmas", on: day(2026, 12, 24), dollars(1650), paidBy: cat, among: [amy, ben, cat])
        try g.convert("bistro", into: bill)
        // $200 hotpot + $550 real share; the $500 estimate is gone, not double counted.
        #expect(g.committedSpend(for: amy, in: december, calendar: hongKong).total == dollars(750))
    }

    @Test func expensesOfATripAcrossMonthsLandInTheirOwnMonths() {
        let trip = GroupState(
            members: members(amy, ben),
            activities: [Activity(id: "trip", name: "台北", date: day(2026, 12, 30), organiser: amy, attendance: going(amy, ben))],
            expenses: [
                expense("hotel", in: "trip", on: day(2026, 12, 30), dollars(2000), paidBy: amy, among: [amy, ben]),
                expense("night market", in: "trip", on: day(2027, 1, 2), dollars(300), paidBy: ben, among: [amy, ben]),
            ]
        )
        #expect(trip.committedSpend(for: amy, in: december, calendar: hongKong).total == dollars(1000))
        #expect(trip.committedSpend(for: amy, in: january, calendar: hongKong).total == dollars(150))
    }

    @Test func monthBoundaryFollowsTheDeviceCalendar() {
        // 00:30 on 1 Jan in Hong Kong is still 31 Dec in UTC.
        let justAfterMidnight = hongKong.date(from: DateComponents(year: 2027, month: 1, day: 1, hour: 0, minute: 30))!
        let g = GroupState(
            members: members(amy),
            expenses: [expense("taxi", on: justAfterMidnight, dollars(100), paidBy: amy, among: [amy])]
        )
        #expect(g.committedSpend(for: amy, in: january, calendar: hongKong).total == dollars(100))
        #expect(g.committedSpend(for: amy, in: december, calendar: hongKong).total == .zero)
    }

    @Test func proposalThatFitsShowsWhatIsLeftThisMonth() throws {
        var g = friends
        g.proposals[0].status = .open
        let check = try #require(personalCheck(
            for: "bistro", viewer: me, budget: dollars(1000), across: [g], asOf: day(2026, 12, 1), calendar: hongKong))
        #expect(check.month == december)
        #expect(check.share == dollars(500))
        #expect(check.committedAfter == dollars(700))
        #expect(check.remaining == dollars(300))
        #expect(!check.isOver)
    }

    @Test func proposalThatBreaksTheBudgetIsFlaggedWithTheOverspend() throws {
        let check = try #require(personalCheck(
            for: "omakase", viewer: me, budget: dollars(1000), across: [friends], asOf: day(2026, 12, 1), calendar: hongKong))
        #expect(check.isOver)
        #expect(check.remaining == dollars(-700))
    }

    @Test func proposalReplacesTheChosenOneForTheSameActivityRatherThanAddingToIt() throws {
        // Omakase would take the bistro's place: 200 + 1500, not 200 + 500 + 1500.
        let check = try #require(personalCheck(
            for: "omakase", viewer: me, budget: dollars(3000), across: [friends], asOf: day(2026, 12, 1), calendar: hongKong))
        #expect(check.committedAfter == dollars(1700))
    }

    @Test func checkingTheAlreadyChosenProposalDoesNotCountItTwice() throws {
        let check = try #require(personalCheck(
            for: "bistro", viewer: me, budget: dollars(1000), across: [friends], asOf: day(2026, 12, 1), calendar: hongKong))
        #expect(check.committedAfter == dollars(700))
    }

    @Test func someoneWhoHasNotRepliedIsCheckedAsIfTheyWent() throws {
        var g = friends
        g.activities[1].attendance[amy] = .noReply
        let check = try #require(personalCheck(
            for: "bistro", viewer: me, budget: dollars(1000), across: [g], asOf: day(2026, 12, 1), calendar: hongKong))
        #expect(check.committedAfter == dollars(700))
    }

    @Test func committedSpendRunsAcrossEveryGroupIAmIn() throws {
        let work = GroupState(
            members: [Member(id: "amy@work", name: "Amy"), Member(id: "boss", name: "Boss")],
            expenses: [expense("team lunch", in: "lunch", on: day(2026, 12, 10), dollars(600), paidBy: "boss", among: ["amy@work", "boss"])]
        )
        let all = [friends, work]
        #expect(committedSpend(for: me, in: december, across: all, calendar: hongKong).total == dollars(1000))

        let check = try #require(personalCheck(
            for: "omakase", viewer: me, budget: dollars(1800), across: all, asOf: day(2026, 12, 1), calendar: hongKong))
        #expect(check.committedAfter == dollars(2000))
        #expect(check.remaining == dollars(-200))
    }

    @Test func undatedActivityIsCheckedAgainstTheCurrentMonth() throws {
        var g = friends
        g.activities.append(Activity(id: "someday", name: "遲啲食", organiser: ben))
        g.proposals.append(Proposal(id: "later", activityID: "someday", title: "燒肉", amount: .perPerson(dollars(400))))
        let check = try #require(personalCheck(
            for: "later", viewer: me, budget: dollars(1000), across: [g], asOf: day(2026, 12, 1), calendar: hongKong))
        #expect(check.month == december)
        #expect(check.committedAfter == dollars(1100))
    }

    @Test func noPersonalBudgetMeansNoPersonalCheck() {
        #expect(personalCheck(
            for: "omakase", viewer: me, budget: nil, across: [friends], asOf: day(2026, 12, 1), calendar: hongKong) == nil)
    }
}
