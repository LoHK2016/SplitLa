import SwiftUI

/// Email first, then the 6-digit code that was sent to it.
struct SignInView: View {
    @Environment(SessionModel.self) private var session

    @State private var email = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case email, code }

    var body: some View {
        NavigationStack {
            Form {
                if let sentTo {
                    codeSection(sentTo: sentTo)
                } else {
                    emailSection
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("SplitLa")
            .disabled(isWorking)
        }
    }

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var emailSection: some View {
        Section {
            TextField("電郵地址", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.continue)
                .onSubmit(sendCode)
            Button(action: sendCode) {
                progressLabel("寄驗證碼畀我")
            }
            .disabled(!trimmedEmail.contains("@"))
        } header: {
            Text("登入")
        } footer: {
            Text("我哋會寄一個 6 位數驗證碼去你嘅電郵，唔使密碼。")
        }
    }

    private func codeSection(sentTo: String) -> some View {
        Section {
            TextField("6 位數驗證碼", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focus, equals: .code)
                .onChange(of: code) { _, new in
                    code = String(new.filter(\.isNumber).prefix(6))
                    if code.count == 6 { verify(sentTo) }
                }
            Button { verify(sentTo) } label: {
                progressLabel("登入")
            }
            .disabled(code.count != 6)
            Button("用另一個電郵") {
                self.sentTo = nil
                code = ""
                errorMessage = nil
                focus = .email
            }
        } header: {
            Text("輸入驗證碼")
        } footer: {
            Text("驗證碼已經寄去 \(sentTo)。")
        }
    }

    private func progressLabel(_ title: String) -> some View {
        HStack {
            Text(title)
            if isWorking {
                Spacer()
                ProgressView()
            }
        }
    }

    private func sendCode() {
        let address = trimmedEmail
        guard address.contains("@"), !isWorking else { return }
        run(failure: "寄唔到驗證碼，請檢查電郵地址同網絡再試。") {
            try await session.sendCode(to: address)
            sentTo = address
            focus = .code
        }
    }

    private func verify(_ address: String) {
        guard code.count == 6, !isWorking else { return }
        run(failure: "驗證碼唔啱或者已經過期。") {
            do {
                try await session.verify(code: code, for: address)
            } catch {
                code = ""
                throw error
            }
        }
    }

    private func run(failure: String, _ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do { try await work() } catch { errorMessage = failure }
            isWorking = false
        }
    }
}
