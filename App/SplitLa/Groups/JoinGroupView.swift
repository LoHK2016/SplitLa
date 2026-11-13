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
        case found(groupName: String)
        case failed
    }

    @State private var lookup = Lookup.loading
    @State private var myName = ""
    @State private var isWorking = false
    @State private var joinFailed = false

    var body: some View {
        NavigationStack {
            Group {
                switch lookup {
                case .loading:
                    ProgressView()
                case .failed:
                    ContentUnavailableView {
                        Label("開唔到呢條邀請連結", systemImage: "link.badge.plus")
                    } description: {
                        Text("條連結可能已經失效，或者而家冇網絡。叫朋友再傳一次畀你。")
                    } actions: {
                        Button("再試") { Task { await look() } }
                    }
                case .found(let groupName):
                    form(groupName: groupName)
                }
            }
            .navigationTitle("加入群組")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .task { await look() }
    }

    private func form(groupName: String) -> some View {
        Form {
            Section {
                LabeledContent("群組", value: groupName)
            } footer: {
                Text("加入之後，你會見到呢個群組嘅成員同帳目。")
            }
            Section {
                TextField("你嘅名", text: $myName)
                    .textContentType(.nickname)
            } header: {
                Text("你喺呢個群組叫咩名")
            } footer: {
                Text("其他成員會見到呢個名。")
            }
            if joinFailed {
                Section {
                    Label("加入唔到，請檢查網絡再試。", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button(action: join) {
                    HStack {
                        Text("加入「\(groupName)」")
                        if isWorking {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(myName.trimmed.isEmpty)
            }
        }
        .disabled(isWorking)
    }

    private func look() async {
        lookup = .loading
        do {
            let name = try await model.service.invitedGroupName(invite: invite)
            if myName.isEmpty { myName = user.suggestedName }
            lookup = .found(groupName: name)
        } catch {
            lookup = .failed
        }
    }

    private func join() {
        isWorking = true
        joinFailed = false
        Task {
            do {
                let id = try await model.service.join(invite: invite, myName: myName.trimmed)
                dismiss()
                onDone(id)
            } catch {
                joinFailed = true
            }
            isWorking = false
        }
    }
}
