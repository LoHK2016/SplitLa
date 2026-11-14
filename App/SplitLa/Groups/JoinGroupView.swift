import SwiftUI

/// Sheet shown after opening an invite link: says which Group it is for and asks before joining.
struct JoinGroupView: View {
    @Environment(GroupsModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let invite: UUID
    let user: SignedInUser
    /// Called with the Group's id once the user is a Member.
    let onDone: (UUID) -> Void

    private enum Lookup {
        case loading
        case found(groupName: String, placeholders: [GroupMember])
        case failed
    }

    @State private var lookup = Lookup.loading
    @State private var myName = ""
    @State private var isWorking = false
    @State private var joinFailed = false
    /// The Placeholder Member being claimed; nil to join as a new Member.
    @State private var claim: UUID?

    var body: some View {
        NavigationStack {
            Group {
                switch lookup {
                case .loading:
                    ProgressView()
                case .failed:
                    ContentUnavailableView {
                        Label("This Invite Link Doesn’t Work", systemImage: "link.badge.plus")
                    } description: {
                        Text("It may have expired, or you may be offline. Ask your friend to send it again.")
                    } actions: {
                        Button("Try Again") { Task { await look() } }
                    }
                case .found(let groupName, let placeholders):
                    form(groupName: groupName, placeholders: placeholders)
                }
            }
            .navigationTitle("Join Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await look() }
    }

    private func form(groupName: String, placeholders: [GroupMember]) -> some View {
        Form {
            Section {
                LabeledContent("Group", value: groupName)
            } footer: {
                Text("Once you join, you’ll see this Group’s Members and accounts.")
            }
            if !placeholders.isEmpty {
                Section {
                    Picker("Which one are you?", selection: $claim) {
                        Text("I’m new").tag(UUID?.none)
                        ForEach(placeholders) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Has a Friend Already Added You?")
                } footer: {
                    Text("If one of these is you, pick it and everything recorded for you comes with you.")
                }
            }
            if claim == nil {
                Section {
                    TextField("Your name", text: $myName)
                        .textContentType(.nickname)
                } header: {
                    Text("What Should This Group Call You?")
                } footer: {
                    Text("Other Members will see this name.")
                }
            }
            if joinFailed {
                Section {
                    Label("Couldn’t join. Check your connection and try again.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button(action: join) {
                    HStack {
                        Text("Join “\(groupName)”")
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(claim == nil && myName.trimmed.isEmpty)
                .needsConnection()
            }
        }
        .disabled(isWorking)
    }

    private func look() async {
        lookup = .loading
        do {
            async let name = model.service.invitedGroupName(invite: invite)
            async let placeholders = model.service.placeholders(invite: invite)
            if myName.isEmpty { myName = user.suggestedName }
            lookup = .found(groupName: try await name, placeholders: try await placeholders)
        } catch {
            lookup = .failed
        }
    }

    private func join() {
        isWorking = true
        joinFailed = false
        Task {
            do {
                let id = try await model.service.join(invite: invite, myName: myName.trimmed, claiming: claim)
                dismiss()
                onDone(id)
            } catch {
                joinFailed = true
            }
            isWorking = false
        }
    }
}
