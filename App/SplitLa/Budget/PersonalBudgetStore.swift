import Foundation
import Ledger
import Observation
import SwiftData

/// The Personal Budget as saved on this device. It is never sent anywhere:
/// nothing in this file, or anything that reads it, talks to the server.
@Model
final class PersonalBudgetRecord {
    /// The signed-in user this budget belongs to.
    @Attribute(.unique) var owner: UUID
    var monthlyCents: Int

    init(owner: UUID, monthlyCents: Int) {
        self.owner = owner
        self.monthlyCents = monthlyCents
    }
}

/// The signed-in user's Personal Budget: a monthly limit only they can see.
@MainActor @Observable
final class PersonalBudgetStore {
    /// Nil when no Personal Budget is set.
    private(set) var budget: Money?

    private let container: ModelContainer
    private var owner: UUID?

    init() {
        // A budget that cannot be saved is still usable for this run, so fall back to memory.
        container = (try? ModelContainer(for: PersonalBudgetRecord.self))
            ?? (try! ModelContainer(
                for: PersonalBudgetRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// Shows the budget saved for this user. Call with nil on sign-out.
    func use(owner: UUID?) {
        self.owner = owner
        budget = owner.flatMap(record(for:)).map { Money(cents: $0.monthlyCents) }
    }

    /// Saves a new monthly limit, or removes it with nil.
    func set(_ newBudget: Money?) {
        guard let owner else { return }
        let context = container.mainContext
        let existing = record(for: owner)
        if let newBudget {
            if let existing {
                existing.monthlyCents = newBudget.cents
            } else {
                context.insert(PersonalBudgetRecord(owner: owner, monthlyCents: newBudget.cents))
            }
        } else if let existing {
            context.delete(existing)
        }
        try? context.save()
        budget = newBudget
    }

    private func record(for owner: UUID) -> PersonalBudgetRecord? {
        let wanted = FetchDescriptor<PersonalBudgetRecord>(predicate: #Predicate { $0.owner == owner })
        return try? container.mainContext.fetch(wanted).first
    }
}
