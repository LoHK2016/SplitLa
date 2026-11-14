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
                Section("群組名") {
                    TextField("例如：大學飯腳", text: $groupName)
                        .focused($nameFocused)
                }
                Section {
                    TextField("你嘅名", text: $myName)
                        .textContentType(.nickname)
                } header: {
                    Text("你喺呢個群組叫咩名")
                } footer: {
                    Text("其他成員會見到呢個名。")
                }
                if failed {
                    Section {
                        Label("開唔到群組，請檢查網絡再試。", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("開新群組")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isWorking {
                        ProgressView()
                    } else {
                        Button("建立", action: create)
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

