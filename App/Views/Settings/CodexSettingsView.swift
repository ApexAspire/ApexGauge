import ApexGaugeCore
import SwiftUI

struct CodexSettingsView: View {
    let credentialStore: KeychainCredentialStore

    @State private var accessToken = ""
    @State private var refreshToken = ""
    @State private var accountID = ""
    @State private var isConnected = false
    @State private var isWorking = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("How to connect") {
                Text("On your Mac, run this command in Terminal, then paste each value below:")
                Text(#"jq -r '"access: \(.tokens.access_token)\nrefresh: \(.tokens.refresh_token)\naccount: \(.tokens.account_id)"' ~/.codex/auth.json"#)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("Credentials") {
                SecureField("Access token", text: $accessToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Refresh token", text: $refreshToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Account ID", text: $accountID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Text("After connecting here, this phone becomes the refresh owner — avoid signing in/out of the Codex CLI on the Mac, or re-paste if Codex stops updating.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Section {
                Button("Connect") {
                    Task { await connect() }
                }
                .disabled(!hasAllFields || isWorking)

                if isConnected {
                    Button("Disconnect", role: .destructive) {
                        Task { await disconnect() }
                    }
                    .disabled(isWorking)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(isConnected ? .green : .red)
                }
            }
        }
        .navigationTitle("Codex")
        .task { await loadConnectionState() }
    }

    private var hasAllFields: Bool {
        !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func loadConnectionState() async {
        do {
            isConnected = try await credentialStore.loadCodex() != nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func connect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.saveCodex(
                CodexCredentials(
                    accessToken: accessToken.trimmingCharacters(in: .whitespacesAndNewlines),
                    refreshToken: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines),
                    accountID: accountID.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            accessToken = ""
            refreshToken = ""
            accountID = ""
            isConnected = true
            statusMessage = "Codex credentials saved securely."
        } catch {
            isConnected = false
            statusMessage = error.localizedDescription
        }
    }

    private func disconnect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.clear(provider: .codex)
            accessToken = ""
            refreshToken = ""
            accountID = ""
            isConnected = false
            statusMessage = "Codex disconnected."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
