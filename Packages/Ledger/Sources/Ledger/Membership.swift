extension GroupState {
    /// A person takes over a Placeholder Member. The accounts do not change.
    public mutating func claimPlaceholder(_ id: MemberID) throws {
        guard let index = members.firstIndex(where: { $0.id == id }) else { throw LedgerError.memberNotFound }
        guard members[index].isPlaceholder else { throw LedgerError.notAPlaceholder }
        members[index].isPlaceholder = false
    }

    /// A Member leaves the Group and becomes a Placeholder Member. Their Balance stays.
    public mutating func leave(_ id: MemberID) throws {
        guard let index = members.firstIndex(where: { $0.id == id }) else { throw LedgerError.memberNotFound }
        guard !members[index].isPlaceholder else { throw LedgerError.alreadyAPlaceholder }
        members[index].isPlaceholder = true
    }
}
