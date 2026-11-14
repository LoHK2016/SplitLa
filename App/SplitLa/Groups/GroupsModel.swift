import Foundation
import Ledger
import Network
import Observation

/// An invite link the user opened and has not yet acted on.
struct PendingInvite: Identifiable, Equatable {
    let token: UUID
    var id: UUID { token }
}

/// One Group as a screen needs it: the rows last read, the Ledger's view of them, and who "me" is.
struct GroupContext {
    let snapshot: GroupSnapshot
    let state: GroupState
    /// The signed-in user's Member in this Group.
    let me: GroupMember?

    var id: UUID { snapshot.group.id }

    func name(of member: UUID) -> String {
        snapshot.members.first { $0.id == member }?.name ?? "？"
    }

    func name(of member: MemberID) -> String {
        member.uuid.map(name(of:)) ?? "？"
    }

    func activity(_ id: UUID) -> ActivityRow? { snapshot.activities.first { $0.id == id } }
}

/// Every Group the signed-in user belongs to, kept as last read from the server and saved on the
/// device so it can still be shown with no connection. Nothing is changed while offline.
@MainActor @Observable
final class GroupsModel {
    let service: GroupsService
    var pendingInvite: PendingInvite?

    /// Nil until something has been read from the server or the saved copy.
    private(set) var groups: [GroupSummary]?
    private(set) var snapshots: [UUID: GroupSnapshot] = [:]
    /// True when the last attempt to reach the server failed or the device has no connection.
    /// While true the app only shows what it has; nothing can be added or changed.
    private(set) var isOffline = false

    private var user: SignedInUser?
    /// One live subscription per Group, so every screen stays current whichever one is showing.
    private var watchers: [UUID: Task<Void, Never>] = [:]
    private var hasConnection = true
    private let monitor = NWPathMonitor()

    init(service: GroupsService) {
        self.service = service
    }

    // MARK: Signing in and out

    /// Shows the saved copy at once, then keeps in step with the server until cancelled.
    func run(for user: SignedInUser) async {
        self.user = user
        if let saved = Self.readCache(for: user.id) {
            groups = saved.groups
            snapshots = saved.snapshots
        }
        await reloadAll()
        let paths = AsyncStream<Bool> { continuation in
            monitor.pathUpdateHandler = { continuation.yield($0.status == .satisfied) }
            monitor.start(queue: .global(qos: .utility))
        }
        async let _: Void = retryWhileOffline()
        for await connected in paths {
            let wasConnected = hasConnection
            hasConnection = connected
            if !connected { isOffline = true }
            if connected && !wasConnected { await reloadAll() }
        }
    }

    /// Forgets everything about the user who signed out, including the saved copy.
    func signedOut() {
        if let user { try? FileManager.default.removeItem(at: Self.cacheURL(for: user.id)) }
        user = nil
        groups = nil
        snapshots = [:]
        isOffline = false
        watch([])
    }

    /// Follows changes on the server for exactly these Groups.
    private func watch(_ wanted: Set<UUID>) {
        for (id, task) in watchers where !wanted.contains(id) {
            task.cancel()
            watchers[id] = nil
        }
        for id in wanted where watchers[id] == nil {
            watchers[id] = Task { [weak self, service] in
                for await _ in service.changes(in: id) {
                    await self?.reload(id)
                }
            }
        }
    }

    /// With no change in connection to wait for (the server itself may be down), try again now and then.
    private func retryWhileOffline() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(8))
            if isOffline && hasConnection { await reloadAll() }
        }
    }

    // MARK: Reading

    /// Reads the Group list and every Group. A Personal Budget check runs across all of them.
    func reloadAll() async {
        do {
            let list = try await service.myGroups()
            var fresh: [UUID: GroupSnapshot] = [:]
            try await withThrowingTaskGroup(of: GroupSnapshot?.self) { tasks in
                for group in list {
                    tasks.addTask { try await self.service.snapshot(of: group.id) }
                }
                for try await snapshot in tasks {
                    if let snapshot { fresh[snapshot.group.id] = snapshot }
                }
            }
            groups = list.filter { fresh[$0.id] != nil }
            snapshots = fresh
            synced()
        } catch is CancellationError {
        } catch {
            failed(error)
        }
    }

    /// Reads one Group again, after a change here or a change seen on the server.
    func reload(_ groupID: UUID) async {
        do {
            if let snapshot = try await service.snapshot(of: groupID) {
                snapshots[groupID] = snapshot
                if let index = groups?.firstIndex(where: { $0.id == groupID }) {
                    groups?[index] = snapshot.group
                } else {
                    groups = (groups ?? []) + [snapshot.group]
                }
            } else {
                snapshots[groupID] = nil
                groups?.removeAll { $0.id == groupID }
            }
            synced()
        } catch is CancellationError {
        } catch {
            failed(error)
        }
    }

    func context(_ groupID: UUID) -> GroupContext? {
        guard let snapshot = snapshots[groupID] else { return nil }
        return GroupContext(
            snapshot: snapshot, state: snapshot.ledger,
            me: snapshot.members.first { $0.userID != nil && $0.userID == user?.id })
    }

    /// Every Group in Ledger form, for sums that run across Groups.
    var allStates: [GroupState] { snapshots.values.map(\.ledger) }

    /// The signed-in user as they appear in each Group.
    var identity: MemberIdentity {
        MemberIdentity(memberIDs: Set(snapshots.values.flatMap(\.members)
            .filter { $0.userID != nil && $0.userID == user?.id }.map(\.id.memberID)))
    }

    // MARK: Writing

    /// Runs one change on the server, then reads the Group again so the screen shows the result.
    func change(_ groupID: UUID, _ work: (GroupsService) async throws -> Void) async throws {
        try await work(service)
        await reload(groupID)
    }

    private func synced() {
        isOffline = !hasConnection
        guard let user, let groups else { return }
        watch(Set(groups.map(\.id)))
        let saved = Cache(groups: groups, snapshots: snapshots)
        let url = Self.cacheURL(for: user.id)
        Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(saved).write(to: url, options: .atomic)
        }
    }

    /// Only a failure to reach the server means offline; the server refusing something does not.
    private func failed(_ error: any Error) {
        if error is URLError { isOffline = true }
    }

    // MARK: The saved copy

    private struct Cache: Codable {
        var groups: [GroupSummary]
        var snapshots: [UUID: GroupSnapshot]
    }

    private static func cacheURL(for user: UUID) -> URL {
        URL.applicationSupportDirectory.appending(path: "groups-\(user.uuidString).json")
    }

    private static func readCache(for user: UUID) -> Cache? {
        guard let data = try? Data(contentsOf: cacheURL(for: user)) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }
}
