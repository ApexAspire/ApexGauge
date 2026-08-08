import ApexGaugeCore
import SwiftUI

struct ClaudeSettingsView: View {
    let credentialStore: KeychainCredentialStore

    @State private var refreshToken = ""
    @State private var isConnected = false
    @State private var isWorking = false
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section("How to connect") {
                Text("On your Mac, run this command in Terminal, then paste the refresh token below:")
                Text("jq -r .claudeAiOauth.refreshToken ~/.claude/.credentials.json")
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }

            Section("Refresh token") {
                SecureField("Claude refresh token", text: $refreshToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Button("Connect") {
                    Task { await connect() }
                }
                .disabled(refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

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
        .navigationTitle("Claude")
        .task { await loadConnectionState() }
    }

    private func loadConnectionState() async {
        do {
            isConnected = try await credentialStore.loadClaude() != nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func connect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.saveClaude(
                ClaudeCredentials(
                    accessToken: "",
                    refreshToken: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            )
            refreshToken = ""
            isConnected = true
            statusMessage = "Claude credentials saved securely."
        } catch {
            isConnected = false
            statusMessage = error.localizedDescription
        }
    }

    private func disconnect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.clear(provider: .claude)
            refreshToken = ""
            isConnected = false
            statusMessage = "Claude disconnected."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
