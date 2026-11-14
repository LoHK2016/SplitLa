import SwiftUI

/// Sheet for opening a new Group.
struct NewGroupView: View {
    @Environment(GroupsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let user: SignedInUser
    /// Called with the new Group's id once it exists.
    let onDone: (UUID) -> Void

    @State private var groupName = ""
    @State private var myName = ""
    @State private var isWorking = false
    @State private var failed = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField("e.g. Uni dinner crew", text: $groupName)
                        .focused($nameFocused)
                }
                Section {
                    TextField("Your name", text: $myName)
                        .textContentType(.nickname)
                } header: {
                    Text("What Should This Group Call You?")
                } footer: {
                    Text("Other Members will see this name.")
                }
                if failed {
                    Section {
                        Label("Couldn’t create the Group. Check your connection and try again.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("Create", action: create)
                            .disabled(groupName.trimmed.isEmpty || myName.trimmed.isEmpty)
                            .needsConnection()
                    }
                }
            }
            .disabled(isWorking)
            .onAppear {
                myName = user.suggestedName
                nameFocused = true
            }
        }
    }

    private func create() {
        isWorking = true
        failed = false
        Task {
            do {
                let id = try await model.service.createGroup(named: groupName.trimmed, myName: myName.trimmed)
                dismiss()
                onDone(id)
            } catch {
                failed = true
            }
            isWorking = false
        }
    }
}

