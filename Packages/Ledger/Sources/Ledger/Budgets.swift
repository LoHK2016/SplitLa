import Foundation

/// The group-visible half of a What-if Check: a Proposal against the Activity Budget.
public struct ActivityCheck: Equatable, Sendable {
    public let budget: Money
    /// Expenses already recorded in the Activity.
    public let spent: Money
    public let proposalTotal: Money
    /// Budget left if this Proposal goes ahead. Negative means over budget.
    public var remaining: Money { budget - spent - proposalTotal }
    public var isOver: Bool { remaining < .zero }
}

/// The private half of a What-if Check: a Proposal against one person's Personal Budget.
/// Computed on the device only; nothing here is ever shared with the Group.
public struct PersonalCheck: Equatable, Sendable {
    public let month: YearMonth
    public let budget: Money
    /// The viewer's Share of this Proposal if they go.
    public let share: Money
    /// Committed Spend for the month if this Proposal goes ahead.
    public let committedAfter: Money
    /// Personal Budget left if this Proposal goes ahead. Negative means overspent.
    public var remaining: Money { budget - committedAfter }
    public var isOver: Bool { remaining < .zero }
}

/// One person's Committed Spend for a month, with the items that make it up.
public struct CommittedSpend: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case expense(ExpenseID)
        case chosenProposal(ProposalID)
    }

    public struct Item: Equatable, Sendable {
        public let source: Source
        public let activityID: ActivityID
        public let title: String
        public let amount: Money
    }

    public let items: [Item]
    public var total: Money { items.map(\.amount).sum() }

    /// What is left of a Personal Budget after this Committed Spend. Negative means overspent.
    public func remaining(of budget: Money) -> Money { budget - total }

    /// How much of a Personal Budget this Committed Spend takes up: 0.8 is 80%, over 1 is overspent.
    public func fractionUsed(of budget: Money) -> Double {
        guard budget > .zero else { return total > .zero ? 1 : 0 }
        return Double(total.cents) / Double(budget.cents)
    }
}

extension GroupState {
    /// Checks a Proposal against its Activity Budget. Counts the Activity's recorded
    /// Expenses plus this Proposal only; other Proposals in the Activity are ignored.
    /// Nil when the Activity has no budget.
    public func activityCheck(for proposalID: ProposalID) -> ActivityCheck? {
        guard let proposal = proposal(proposalID), let activity = activity(proposal.activityID),
              let budget = activity.budget, let proposalTotal = total(of: proposalID)
        else { return nil }
        return ActivityCheck(budget: budget, spent: spent(in: activity.id), proposalTotal: proposalTotal)
    }

    /// What the Activity's recorded Expenses add up to, service charge included. Deleted ones do not count.
    public func spent(in activityID: ActivityID) -> Money {
        expenses.filter { $0.activityID == activityID && !$0.isDeleted }.map(\.total).sum()
    }

    /// A member's Committed Spend in this Group for a calendar month: their Shares of
    /// Expenses dated in the month, plus their Shares of Chosen Proposals for Activities
    /// dated in the month that they are going to.
    public func committedSpend(for member: MemberID, in month: YearMonth, calendar: Calendar) -> CommittedSpend {
        var items: [CommittedSpend.Item] = []
        for expense in expenses where !expense.isDeleted && YearMonth(expense.date, calendar: calendar) == month {
            guard let share = expense.shares[member] else { continue }
            items.append(.init(source: .expense(expense.id), activityID: expense.activityID, title: expense.title, amount: share))
        }
        for proposal in proposals where proposal.status == .chosen {
            guard let activity = activity(proposal.activityID), let date = activity.date,
                  YearMonth(date, calendar: calendar) == month,
                  activity.attendance(of: member) == .going,
                  let share = share(of: proposal.id, for: member)
            else { continue }
            items.append(.init(source: .chosenProposal(proposal.id), activityID: activity.id, title: proposal.title, amount: share))
        }
        return CommittedSpend(items: items)
    }
}

/// Checks a Proposal against a Personal Budget. Committed Spend runs across every Group
/// the viewer is in, so this takes all of them. The Proposal replaces, rather than adds to,
/// the Chosen Proposal already counted for the same Activity.
///
/// The month is the Activity's; an Activity with no date yet is checked against the month of `asOf`.
/// Nil when there is no Personal Budget, or the Proposal is unknown or already converted.
public func personalCheck(
    for proposalID: ProposalID, viewer: MemberIdentity, budget: Money?,
    across groups: [GroupState], asOf: Date, calendar: Calendar
) -> PersonalCheck? {
    guard let budget,
          let home = groups.first(where: { $0.proposal(proposalID) != nil }),
          let proposal = home.proposal(proposalID), proposal.status != .converted,
          let activity = home.activity(proposal.activityID),
          let me = viewer.member(in: home),
          let share = home.share(of: proposalID, for: me)
    else { return nil }

    let month = YearMonth(activity.date ?? asOf, calendar: calendar)
    let committed = committedSpend(for: viewer, in: month, across: groups, calendar: calendar)
    let replaced = committed.items
        .filter { item in
            if case .chosenProposal = item.source { return item.activityID == activity.id }
            return false
        }
        .map(\.amount).sum()

    return PersonalCheck(
        month: month, budget: budget, share: share,
        committedAfter: committed.total - replaced + share
    )
}

/// One person's Committed Spend for a month across every Group they are in.
public func committedSpend(
    for viewer: MemberIdentity, in month: YearMonth, across groups: [GroupState], calendar: Calendar
) -> CommittedSpend {
    CommittedSpend(items: groups.flatMap { group -> [CommittedSpend.Item] in
        guard let me = viewer.member(in: group) else { return [] }
        return group.committedSpend(for: me, in: month, calendar: calendar).items
    })
}

/// The same person as they appear in each Group: one MemberID per Group they belong to.
public struct MemberIdentity: Equatable, Sendable {
    public let memberIDs: Set<MemberID>

    public init(memberIDs: Set<MemberID>) { self.memberIDs = memberIDs }

    func member(in group: GroupState) -> MemberID? {
        group.members.first { memberIDs.contains($0.id) }?.id
    }
}
