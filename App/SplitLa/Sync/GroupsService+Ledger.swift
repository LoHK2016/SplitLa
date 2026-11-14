import Foundation
import Ledger
import Supabase

/// Reading a whole Group, and every change a Member can make inside one.
extension GroupsService {
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let withFraction = ISO8601DateFormatter()
            withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: text))
            }
            return date
        }
        return decoder
    }()

    private func rows<Row: Decodable>(_ table: String, in group: UUID, order: String = "created_at") async throws -> [Row] {
        let data = try await client.from(table).select().eq("group_id", value: group).order(order).execute().data
        return try Self.decoder.decode([Row].self, from: data)
    }

    /// Everything in a Group, read in one go. Nil when the user no longer belongs to it.
    func snapshot(of groupID: UUID) async throws -> GroupSnapshot? {
        async let group = self.group(groupID)
        async let members = self.members(of: groupID)
        async let activities: [ActivityRow] = rows("activities", in: groupID)
        async let attendance: [AttendanceRow] = rows("attendance", in: groupID, order: "activity_id")
        async let expenses: [ExpenseRow] = rows("expenses", in: groupID)
        async let proposals: [ProposalRow] = rows("proposals", in: groupID)
        async let settlements: [SettlementRow] = rows("settlements", in: groupID)
        guard let found = try await group else { return nil }
        return try await GroupSnapshot(
            group: found, members: members, activities: activities, attendance: attendance,
            expenses: expenses, proposals: proposals, settlements: settlements)
    }

    /// Every recorded change to one Expense or Settlement, oldest first.
    func history(of entity: UUID) async throws -> [ChangeRow] {
        let data = try await client.from("change_log").select().eq("entity_id", value: entity).order("id").execute().data
        return try Self.decoder.decode([ChangeRow].self, from: data)
    }

    // MARK: Members

    func addPlaceholder(named name: String, to group: UUID) async throws {
        try await client.from("members")
            .insert(["group_id": group.uuidString, "name": name], returning: .minimal).execute()
    }

    func leave(_ group: UUID) async throws {
        try await client.rpc("leave_group", params: ["target_group": group.uuidString]).execute()
    }

    // MARK: Activities

    func createActivity(named name: String, on date: Day?, in group: UUID, organiser: UUID) async throws {
        try await client.from("activities").insert([
            "group_id": .string(group.uuidString), "name": .string(name),
            "date": date.map { .string($0.text) } ?? .null, "organiser_id": .string(organiser.uuidString),
        ] as [String: AnyJSON], returning: .minimal).execute()
    }

    /// Sets the Activity Budget, or removes it with nil. The server only lets the Organiser.
    func setBudget(_ budget: Money?, for activity: UUID) async throws {
        try await client.rpc("set_activity_budget", params: [
            "target_activity": .string(activity.uuidString),
            "new_budget_cents": budget.map { .integer($0.cents) } ?? .null,
        ] as [String: AnyJSON]).execute()
    }

    func setAttendance(_ attendance: Attendance, of member: UUID, for activity: UUID) async throws {
        try await client.rpc("set_attendance", params: [
            "target_activity": activity.uuidString, "target_member": member.uuidString,
            "new_status": attendance.serverValue,
        ]).execute()
    }

    // MARK: Expenses

    /// What a Member fills in for an Expense.
    struct ExpenseInput: Sendable {
        var title: String
        var date: Day
        var amount: Money
        var paidBy: UUID
        var split: SplitRow
        var hasServiceCharge: Bool
        /// Set when split by plates; saving without it clears any plates the Expense had.
        var plates: PlatesRow?

        fileprivate var fields: [String: AnyJSON] {
            var split: [String: AnyJSON] = ["kind": .string(self.split.kind)]
            if let members = self.split.members {
                split["members"] = .array(members.map { .string($0.uuidString.lowercased()) })
            }
            if let amounts = self.split.amounts {
                split["amounts"] = .object(amounts.mapValues { .integer($0) })
            }
            return [
                "title": .string(title), "date": .string(date.text), "amount_cents": .integer(amount.cents),
                "paid_by": .string(paidBy.uuidString), "split": .object(split),
                "has_service_charge": .bool(hasServiceCharge),
                "plates": plates.map { plates in
                    .object([
                        "types": .array(plates.types.map { type in
                            .object([
                                "kind": .string(type.kind), "name": .string(type.name),
                                "price_cents": .integer(type.priceCents), "color_index": .integer(type.colorIndex),
                            ])
                        }),
                        "counts": .object(plates.counts.mapValues { .array($0.map { .integer($0) }) }),
                    ])
                } ?? .null,
            ]
        }
    }

    /// Records a new Expense. With `proposal`, it is the real Expense for that Chosen Proposal,
    /// which the server retires in the same step.
    func addExpense(_ input: ExpenseInput, to activity: UUID, in group: UUID, from proposal: UUID? = nil) async throws {
        var fields = input.fields
        fields["group_id"] = .string(group.uuidString)
        fields["activity_id"] = .string(activity.uuidString)
        if let proposal { fields["proposal_id"] = .string(proposal.uuidString) }
        try await client.from("expenses").insert(fields, returning: .minimal).execute()
    }

    func updateExpense(_ expense: UUID, to input: ExpenseInput) async throws {
        try await client.from("expenses").update(input.fields, returning: .minimal).eq("id", value: expense).execute()
    }

    /// Deleting keeps the row for the record; it just stops counting.
    func deleteExpense(_ expense: UUID) async throws {
        try await softDelete("expenses", expense)
    }

    // MARK: Settlements

    func addSettlement(from payer: UUID, to payee: UUID, amount: Money, on date: Day, in group: UUID) async throws {
        try await client.from("settlements").insert([
            "group_id": .string(group.uuidString), "from_member": .string(payer.uuidString),
            "to_member": .string(payee.uuidString), "amount_cents": .integer(amount.cents),
            "date": .string(date.text),
        ] as [String: AnyJSON], returning: .minimal).execute()
    }

    func updateSettlement(_ settlement: UUID, from payer: UUID, to payee: UUID, amount: Money, on date: Day) async throws {
        try await client.from("settlements").update([
            "from_member": .string(payer.uuidString), "to_member": .string(payee.uuidString),
            "amount_cents": .integer(amount.cents), "date": .string(date.text),
        ] as [String: AnyJSON], returning: .minimal).eq("id", value: settlement).execute()
    }

    func deleteSettlement(_ settlement: UUID) async throws {
        try await softDelete("settlements", settlement)
    }

    private func softDelete(_ table: String, _ id: UUID) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        try await client.from(table).update(["deleted_at": now], returning: .minimal).eq("id", value: id).execute()
    }

    // MARK: Proposals

    func addProposal(titled title: String, amount: ProposalAmount, to activity: UUID, in group: UUID) async throws {
        let (kind, money): (String, Money) = switch amount {
        case .perPerson(let each): ("per_person", each)
        case .total(let total): ("total", total)
        }
        try await client.from("proposals").insert([
            "group_id": .string(group.uuidString), "activity_id": .string(activity.uuidString),
            "title": .string(title), "amount_kind": .string(kind), "amount_cents": .integer(money.cents),
        ] as [String: AnyJSON], returning: .minimal).execute()
    }

    /// Makes this the Chosen Proposal of its Activity. The server only lets the Organiser.
    func choose(_ proposal: UUID) async throws {
        try await client.rpc("choose_proposal", params: ["target_proposal": proposal.uuidString]).execute()
    }

    func unchoose(_ proposal: UUID) async throws {
        try await client.rpc("unchoose_proposal", params: ["target_proposal": proposal.uuidString]).execute()
    }
}
