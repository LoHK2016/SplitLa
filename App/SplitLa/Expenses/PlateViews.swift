import Ledger
import SwiftUI

/// One kind of plate on the belt: its colour, its name, and its price as typed.
struct PlateType: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case red, silver, gold, black, custom }

    var id = UUID()
    var kind: Kind
    /// Only used for plates someone added themselves; the coloured plates name themselves.
    var name = ""
    var price: String
    /// Which of the extra colours an added plate gets.
    var colorIndex = 0

    /// What the plate is called on screen.
    func displayName(position: Int) -> String {
        switch kind {
        case .red: String(localized: "Red plate")
        case .silver: String(localized: "Silver plate")
        case .gold: String(localized: "Gold plate")
        case .black: String(localized: "Black plate")
        case .custom: name.trimmed.isEmpty ? String(localized: "Plate \(position + 1)") : name.trimmed
        }
    }

    var color: Color {
        switch kind {
        case .red: Color(red: 0.85, green: 0.20, blue: 0.17)
        case .silver: Color(red: 0.74, green: 0.76, blue: 0.79)
        case .gold: Color(red: 0.85, green: 0.65, blue: 0.13)
        case .black: Color(red: 0.11, green: 0.11, blue: 0.12)
        case .custom: Self.extraColors[colorIndex % Self.extraColors.count]
        }
    }

    static let extraColors: [Color] = [.blue, .green, .purple, .orange, .pink, .teal]

    /// Sushiro's plates, the starting point.
    static let sushiro: [PlateType] = [
        PlateType(kind: .red, price: "12"),
        PlateType(kind: .silver, price: "17"),
        PlateType(kind: .gold, price: "22"),
        PlateType(kind: .black, price: "27"),
    ]
}

extension PlateType {
    /// A kind of plate as saved with an Expense.
    init(saved: PlatesRow.PlateKind) {
        self.init(
            kind: Kind(rawValue: saved.kind) ?? .custom, name: saved.name,
            price: Money(cents: saved.priceCents).plain, colorIndex: saved.colorIndex)
    }
}

extension PlatesRow {
    /// The plates as counted in the form, ready to save. Nil while a price is not valid.
    init?(types: [PlateType], tally: PlateTally) {
        guard tally.prices.count == types.count else { return nil }
        self.init(
            types: zip(types, tally.prices).map { type, price in
                PlateKind(kind: type.kind.rawValue, name: type.name.trimmed, priceCents: price.cents, colorIndex: type.colorIndex)
            },
            counts: tally.counts.filter { $0.value.contains { $0 > 0 } }.reduce(into: [:]) { result, entry in
                result[entry.key.rawValue.lowercased()] = Array(entry.value.prefix(types.count))
            })
    }

    /// The saved plates, back in the form the counters work with.
    var tally: PlateTally {
        PlateTally(
            prices: types.map { Money(cents: $0.priceCents) },
            counts: Dictionary(uniqueKeysWithValues: counts.map { (MemberID($0.key.lowercased()), $0.value) }))
    }

    /// How many plates of each kind one Member took, leaving out the kinds they took none of.
    func plates(of member: UUID) -> [(type: PlateType, count: Int)] {
        let row = counts[member.uuidString.lowercased()] ?? []
        return zip(types, row).compactMap { kind, count in
            count > 0 ? (PlateType(saved: kind), count) : nil
        }
    }
}

/// The plates used last time on this iPhone, so the next meal at the same place is quick.
/// A convenience only: nothing here is shared with the Group or the server.
enum RememberedPlates {
    private static let key = "plateTypes"

    static var value: [PlateType] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let saved = try? JSONDecoder().decode([PlateType].self, from: data), !saved.isEmpty
            else { return PlateType.sushiro }
            return saved
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }
}

/// A plate's colour as a small circle, outlined so silver and black show on any background.
struct PlateDot: View {
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The kinds of plate and their prices. Starts with Sushiro's; prices can be changed, plates
/// added (with a name) or removed.
struct PlatePricesSection: View {
    @Binding var types: [PlateType]
    /// Called with the position of a plate that was removed, so the counts can follow.
    let removed: (Int) -> Void

    var body: some View {
        Section {
            ForEach(types) { type in
                let position = types.firstIndex(of: type) ?? 0
                HStack(spacing: 12) {
                    PlateDot(color: type.color)
                    if type.kind == .custom {
                        TextField(String(localized: "Plate \(position + 1)"), text: field(\.name, of: type.id))
                    } else {
                        Text(type.displayName(position: position))
                    }
                    Spacer(minLength: 8)
                    AmountField(title: "$0", text: field(\.price, of: type.id))
                        .frame(maxWidth: 90)
                }
            }
            .onDelete { offsets in
                for index in offsets.sorted(by: >) {
                    types.remove(at: index)
                    removed(index)
                }
            }
            Button("Add a Plate", systemImage: "plus") {
                let used = types.filter { $0.kind == .custom }.count
                types.append(PlateType(kind: .custom, price: "", colorIndex: used))
            }
            Button("Use Sushiro Plates", systemImage: "arrow.counterclockwise") {
                for index in types.indices.reversed() { removed(index) }
                types = PlateType.sushiro
            }
        } header: {
            Text("Plates")
        } footer: {
            Text("Starts with Sushiro’s plates. Change a price, add your own plate with a name, or swipe left to remove one.")
        }
    }
}

extension PlatePricesSection {
    /// A text field's link to one plate, found by its id each time rather than by position.
    /// A field still being edited when its plate is removed (by a reset or a swipe) writes its
    /// last value on the way out; with a position that would point past the end of the list.
    fileprivate func field(_ keyPath: WritableKeyPath<PlateType, String>, of id: UUID) -> Binding<String> {
        Binding(
            get: { types.first { $0.id == id }?[keyPath: keyPath] ?? "" },
            set: { value in
                if let index = types.firstIndex(where: { $0.id == id }) { types[index][keyPath: keyPath] = value }
            })
    }
}

/// One person's plates: a native stepper for each kind of plate, and what they come to.
struct PlateCounterSection: View {
    let name: String
    let member: MemberID
    let types: [PlateType]
    /// The price of each plate, with any not yet valid counted as nothing.
    let prices: [Money]
    @Binding var plates: PlateTally

    var body: some View {
        let amount = PlateTally(prices: prices, counts: plates.counts).amounts[member]
        Section {
            ForEach(Array(types.enumerated()), id: \.element.id) { index, type in
                let count = plates.count(of: member, priceAt: index)
                Stepper(value: Binding(get: { count }, set: { change($0 - count, at: index) }), in: 0...99) {
                    HStack(spacing: 12) {
                        PlateDot(color: type.color)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(type.displayName(position: index))
                            Text(prices[index].description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer(minLength: 4)
                        Text(verbatim: String(count))
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(count == 0 ? .tertiary : .primary)
                    }
                }
                .accessibilityValue(Text("\(count) plates"))
            }
        } header: {
            HStack {
                Text(name)
                Spacer()
                Text((amount ?? .zero).description).monospacedDigit()
            }
            .font(.headline)
            .foregroundStyle(amount == nil ? .secondary : .primary)
            .textCase(nil)
        }
    }

    private func change(_ amount: Int, at index: Int) {
        var updated = plates
        updated.prices = prices
        updated.add(amount, to: member, priceAt: index)
        plates = updated
    }
}

/// One person's plates in a line: a coloured dot and a count for each kind they took.
struct PlateSummary: View {
    let plates: [(type: PlateType, count: Int)]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(plates.enumerated()), id: \.offset) { position, plate in
                HStack(spacing: 3) {
                    PlateDot(color: plate.type.color, size: 11)
                    Text(verbatim: "×\(plate.count)").monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: "\(plate.count) \(plate.type.displayName(position: position))"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}
