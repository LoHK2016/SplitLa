import Foundation

/// How a Proposal's estimated cost was entered.
public enum ProposalAmount: Equatable, Sendable {
    case perPerson(Money)
    case total(Money)
}

public enum ProposalStatus: Equatable, Sendable {
    case open
    /// The Chosen Proposal: at most one per Activity.
    case chosen
    /// The Activity happened and this Proposal was turned into an Expense.
    case converted
}

/// An estimated cost within an Activity that has not happened yet.
public struct Proposal: Identifiable, Equatable, Sendable {
    public let id: ProposalID
    public let activityID: ActivityID
    public var title: String
    public var amount: ProposalAmount
    public var status: ProposalStatus

    public init(
        id: ProposalID, activityID: ActivityID, title: String, amount: ProposalAmount,
        status: ProposalStatus = .open
    ) {
        self.id = id
        self.activityID = activityID
        self.title = title
        self.amount = amount
        self.status = status
    }
}

/// The starting point for the Expense a Chosen Proposal becomes. The person converting
/// it supplies the real amount and who paid.
public struct ExpenseDraft: Equatable, Sendable {
    public let activityID: ActivityID
    public let title: String
    public let amount: Money
    public let participants: Set<MemberID>
}

extension GroupState {
    /// The Share `member` would carry if they go. For someone who has not replied or
    /// said no, this is the "what if I go" figure: the headcount includes them.
    public func share(of proposalID: ProposalID, for member: MemberID) -> Money? {
        guard let proposal = proposal(proposalID), let activity = activity(proposal.activityID) else { return nil }
        switch proposal.amount {
        case .perPerson(let each):
            return each
        case .total(let total):
            let going = Set(activity.goingMembers).union([member]).sorted()
            let parts = total.splitEvenly(into: going.count)
            return parts[going.firstIndex(of: member)!]
        }
    }

    /// What the Proposal costs the whole Group, using the members who replied "going".
    public func total(of proposalID: ProposalID) -> Money? {
        guard let proposal = proposal(proposalID), let activity = activity(proposal.activityID) else { return nil }
        switch proposal.amount {
        case .perPerson(let each): return each * activity.goingMembers.count
        case .total(let total): return total
        }
    }

    /// Makes a Proposal the Chosen Proposal of its Activity, replacing any other.
    public mutating func choose(_ proposalID: ProposalID, by actor: MemberID) throws {
        let (index, activity) = try locate(proposalID)
        guard activity.organiser == actor else { throw LedgerError.notOrganiser }
        guard activity.date != nil else { throw LedgerError.activityHasNoDate }
        guard proposals[index].status != .converted else { throw LedgerError.proposalNotOpenOrChosen }
        for other in proposals.indices
        where proposals[other].activityID == activity.id && proposals[other].status == .chosen {
            proposals[other].status = .open
        }
        proposals[index].status = .chosen
    }

    /// Returns a Chosen Proposal to open, leaving the Activity with none chosen.
    public mutating func unchoose(_ proposalID: ProposalID, by actor: MemberID) throws {
        let (index, activity) = try locate(proposalID)
        guard activity.organiser == actor else { throw LedgerError.notOrganiser }
        guard proposals[index].status == .chosen else { throw LedgerError.proposalNotChosen }
        proposals[index].status = .open
    }

    /// The pre-filled Expense for a Chosen Proposal: its estimated total, shared by those going.
    public func expenseDraft(for proposalID: ProposalID) throws -> ExpenseDraft {
        let (index, activity) = try locate(proposalID)
        let proposal = proposals[index]
        guard proposal.status == .chosen else { throw LedgerError.proposalNotChosen }
        return ExpenseDraft(
            activityID: activity.id, title: proposal.title,
            amount: total(of: proposalID)!, participants: Set(activity.goingMembers)
        )
    }

    /// Records the real Expense for a Chosen Proposal and retires the Proposal, so the
    /// estimate stops counting towards anyone's Committed Spend.
    public mutating func convert(_ proposalID: ProposalID, into expense: Expense) throws {
        let (index, _) = try locate(proposalID)
        guard proposals[index].status == .chosen else { throw LedgerError.proposalNotChosen }
        proposals[index].status = .converted
        expenses.append(expense)
    }

    private func locate(_ proposalID: ProposalID) throws -> (index: Int, activity: Activity) {
        guard let index = proposals.firstIndex(where: { $0.id == proposalID }) else {
            throw LedgerError.proposalNotFound
        }
        guard let activity = activity(proposals[index].activityID) else { throw LedgerError.activityNotFound }
        return (index, activity)
    }
}
