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
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.continue)
                .onSubmit(sendCode)
            Button(action: sendCode) {
                progressLabel("Send Me a Code")
            }
            .disabled(!trimmedEmail.contains("@"))
        } header: {
            Text("Sign In")
        } footer: {
            Text("We’ll email you a 6-digit code. No password needed.")
        }
    }

    private func codeSection(sentTo: String) -> some View {
        Section {
            TextField("6-digit code", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .focused($focus, equals: .code)
                .onChange(of: code) { _, new in
                    code = String(new.filter(\.isNumber).prefix(6))
                    if code.count == 6 { verify(sentTo) }
                }
            Button { verify(sentTo) } label: {
                progressLabel("Sign In")
            }
            .disabled(code.count != 6)
            Button("Use a Different Email") {
                self.sentTo = nil
                code = ""
                errorMessage = nil
                focus = .email
            }
        } header: {
            Text("Enter Code")
        } footer: {
            Text("Code sent to \(sentTo).")
        }
    }

    private func progressLabel(_ title: LocalizedStringKey) -> some View {
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
        run(failure: String(localized: "Couldn’t send the code. Check the email address and your connection, then try again.")) {
            try await session.sendCode(to: address)
            sentTo = address
            focus = .code
        }
    }

    private func verify(_ address: String) {
        guard code.count == 6, !isWorking else { return }
        run(failure: String(localized: "That code is wrong or has expired.")) {
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
