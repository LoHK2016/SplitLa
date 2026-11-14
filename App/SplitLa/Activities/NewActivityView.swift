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
                Section("活動名") {
                    TextField("例如：星期六火鍋", text: $name).focused($nameFocused)
                }
                Section {
                    Toggle("已經定咗日期", isOn: $hasDate)
                    if hasDate {
                        DatePicker("日期", selection: $date, displayedComponents: .date)
                    }
                } footer: {
                    Text("未定日期都開得，不過要有日期先可以選定提案。")
                }
            }
            .navigationTitle("開新活動")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("建立", action: create)
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
