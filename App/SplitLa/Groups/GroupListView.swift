import SwiftUI

/// The signed-in home screen: the Groups this person belongs to.
struct GroupListView: View {
    @Environment(SessionModel.self) private var session
    let email: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "未有群組",
                systemImage: "person.3",
                description: Text("開一個群組，或者叫朋友傳條邀請連結畀你。")
            )
            .navigationTitle("群組")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Section(email) {
                            Button("登出", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                Task { await session.signOut() }
                            }
                        }
                    } label: {
                        Label("帳戶", systemImage: "person.crop.circle")
                    }
                }
            }
        }
    }
}
