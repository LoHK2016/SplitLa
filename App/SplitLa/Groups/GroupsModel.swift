import Foundation
import Observation

/// An invite link the user opened and has not yet acted on.
struct PendingInvite: Identifiable, Equatable {
    let token: UUID
    var id: UUID { token }
}

/// What the Group screens share: the way to reach the server, and any invite waiting to be answered.
@MainActor @Observable
final class GroupsModel {
    let service: GroupsService
    var pendingInvite: PendingInvite?

    init(service: GroupsService) {
        self.service = service
    }
}
