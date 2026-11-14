import SwiftUI

/// Sheet for opening an Activity. Whoever opens it is its Organiser.
struct NewActivityView: View {
    @Environment(GroupsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID

    @State private var name = ""
    @State private var hasDate = true
    @State private var date = Date()
    @State private var isWorking = false
    @State private var failure: String?
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Saturday hotpot", text: $name).focused($nameFocused)
                }
                Section {
                    Toggle("The date is set", isOn: $hasDate)
                    if hasDate {
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                } footer: {
                    Text("You can add the date later, but a Proposal can only be chosen once there is one.")
                }
            }
            .navigationTitle("New Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(name.trimmed.isEmpty || isWorking)
                        .needsConnection()
                }
            }
            .onAppear { nameFocused = true }
            .failureAlert($failure)
        }
    }

    private func create() {
        guard let me = model.context(groupID)?.me else { return }
        isWorking = true
        Task {
            do {
                try await model.change(groupID) {
                    try await $0.createActivity(
                        named: name.trimmed, on: hasDate ? Day(date) : nil, in: groupID, organiser: me.id)
                }
                dismiss()
            } catch {
                failure = failureMessage(error)
            }
            isWorking = false
        }
    }
}
