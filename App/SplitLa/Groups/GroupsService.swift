import Foundation
import Supabase

/// A Group as the list and detail screens need it.
struct GroupSummary: Identifiable, Hashable, Decodable, Sendable {
    let id: UUID
    var name: String
    /// Whoever holds this can join. Only Members can read it.
    let inviteToken: UUID

    enum CodingKeys: String, CodingKey {
        case id, name
        case inviteToken = "invite_token"
    }
}

struct GroupMember: Identifiable, Hashable, Decodable, Sendable {
    let id: UUID
    var name: String
    /// Nil for a Placeholder Member.
    let userID: UUID?

    enum CodingKeys: String, CodingKey {
        case id, name
        case userID = "user_id"
    }
}

/// Reading and changing Groups and their Members on the server.
/// The server decides who may see what; this only asks.
struct GroupsService: Sendable {
    let client: SupabaseClient

    /// Every Group the signed-in user belongs to, oldest first.
    func myGroups() async throws -> [GroupSummary] {
        try await client.from("groups")
            .select("id, name, invite_token")
            .order("created_at")
            .execute().value
    }

    /// Nil when the Group is gone or the user no longer belongs to it.
    func group(_ id: UUID) async throws -> GroupSummary? {
        let rows: [GroupSummary] = try await client.from("groups")
            .select("id, name, invite_token")
            .eq("id", value: id)
            .execute().value
        return rows.first
    }

    func members(of group: UUID) async throws -> [GroupMember] {
        try await client.from("members")
            .select("id, name, user_id")
            .eq("group_id", value: group)
            .order("created_at")
            .order("id")
            .execute().value
    }

    /// Opens a Group with the signed-in user as its first Member.
    func createGroup(named name: String, myName: String) async throws -> UUID {
        try await client.rpc("create_group", params: ["group_name": name, "member_name": myName])
            .execute().value
    }

    func rename(_ group: UUID, to name: String) async throws {
        try await client.from("groups").update(["name": name]).eq("id", value: group).execute()
    }

    /// The name of the Group an invite is for. Throws if the invite is not valid.
    func invitedGroupName(invite: UUID) async throws -> String {
        try await client.rpc("invited_group_name", params: ["invite": invite.uuidString])
            .execute().value
    }

    /// Joins the Group an invite is for; harmless if already a Member. Returns the Group's id.
    func join(invite: UUID, myName: String) async throws -> UUID {
        try await client.rpc("join_group", params: ["invite": invite.uuidString, "member_name": myName])
            .execute().value
    }

    /// Fires each time the Group or its Member list changes on the server,
    /// for as long as the stream is being read.
    func changes(in group: UUID) -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                let channel = client.channel("group-\(group.uuidString)")
                let memberChanges = channel.postgresChange(
                    AnyAction.self, table: "members", filter: .eq("group_id", value: group))
                let groupChanges = channel.postgresChange(
                    AnyAction.self, table: "groups", filter: .eq("id", value: group))
                // If this fails the screen simply stops updating by itself; pull-to-refresh still works.
                try? await channel.subscribeWithError()
                await withTaskGroup(of: Void.self) { tasks in
                    tasks.addTask { for await _ in memberChanges { continuation.yield() } }
                    tasks.addTask { for await _ in groupChanges { continuation.yield() } }
                }
                continuation.finish()
                // Reading stops by cancelling this task, so the clean-up needs its own.
                Task.detached { await client.removeChannel(channel) }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// The link a Member shares so a friend can join their Group.
enum InviteLink {
    static func url(for invite: UUID) -> URL {
        var parts = URLComponents()
        parts.scheme = "splitla"
        parts.host = "join"
        parts.queryItems = [URLQueryItem(name: "token", value: invite.uuidString.lowercased())]
        return parts.url!
    }

    /// The invite in a link, or nil if the link is not an invite.
    static func invite(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == "splitla", url.host?.lowercased() == "join",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let token = parts.queryItems?.first(where: { $0.name == "token" })?.value
        else { return nil }
        return UUID(uuidString: token)
    }
}
