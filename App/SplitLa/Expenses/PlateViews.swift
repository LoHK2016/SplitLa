import Ledger
import SwiftUI

/// The plate prices used last time on this iPhone, so the next meal at the same place is quick.
/// A convenience only: nothing here is shared with the Group or the server.
enum PlatePrices {
    private static let key = "platePrices"
    /// A typical conveyor-belt sushi price list, used until someone saves their own.
    static let starting = [12, 17, 22, 27].map(Money.init(dollars:))

    static var remembered: [Money] {
        get {
            let cents = UserDefaults.standard.array(forKey: key) as? [Int] ?? []
            return cents.isEmpty ? starting : cents.map(Money.init(cents:))
        }
        set { UserDefaults.standard.set(newValue.map(\.cents), forKey: key) }
    }
}

/// The price of each kind of plate. Prices differ between restaurants, so they can be changed,
/// added or removed.
struct PlatePricesSection: View {
    @Binding var texts: [String]

    var body: some View {
        Section {
            ForEach(texts.indices, id: \.self) { index in
                LabeledContent("Plate \(index + 1)") {
                    AmountField(title: "$0", text: $texts[index])
                }
            }
            .onDelete { texts.remove(atOffsets: $0) }
            Button("Add a Plate Price", systemImage: "plus") { texts.append("") }
            Button("Use Usual Prices", systemImage: "arrow.counterclockwise") {
                texts = PlatePrices.starting.map(\.plain)
            }
        } header: {
            Text("Plate Prices")
        } footer: {
            Text("Set these to the prices on the restaurant’s menu. Swipe to remove one.")
        }
    }
}

/// One person's plates: their amount so far, and a counter for each plate price.
struct PlateCounter: View {
    let name: String
    let member: MemberID
    let prices: [Money]
    @Binding var plates: PlateTally

    var body: some View {
        let tally = PlateTally(prices: prices, counts: plates.counts)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(name).font(.headline)
                Spacer()
                Text((tally.amounts[member] ?? .zero).description)
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tally.amounts[member] == nil ? .secondary : .primary)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(prices.indices, id: \.self) { index in
                    let count = plates.count(of: member, priceAt: index)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(prices[index].description)
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        HStack(spacing: 0) {
                            Button { change(-1, at: index) } label: {
                                Image(systemName: "minus")
                                    .font(.footnote.weight(.bold))
                                    .frame(width: 34, height: 34)
                                    .background(Color(.systemBackground), in: Circle())
                            }
                            .disabled(count == 0)
                            .accessibilityLabel("One fewer \(prices[index].description) plate for \(name)")
                            Text(verbatim: String(count))
                                .font(.system(.title3, design: .rounded).weight(.bold))
                                .monospacedDigit()
                                .frame(maxWidth: .infinity)
                            Button { change(1, at: index) } label: {
                                Image(systemName: "plus")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 34, height: 34)
                                    .background(Color.accentColor, in: Circle())
                            }
                            .accessibilityLabel("One more \(prices[index].description) plate for \(name)")
                        }
                    }
                    // Without this, a tap anywhere in the row would press every button in it.
                    .buttonStyle(.borderless)
                    .padding(10)
                    .background(
                        count > 0 ? Color.accentColor.opacity(0.10) : Color(.tertiarySystemFill),
                        in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func change(_ amount: Int, at index: Int) {
        var updated = plates
        updated.prices = prices
        updated.add(amount, to: member, priceAt: index)
        plates = updated
    }
}
