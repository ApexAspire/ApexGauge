import ApexGaugeCore
import SwiftUI

struct ClaudeSettingsView: View {
    let credentialStore: KeychainCredentialStore

    @State private var pastedCredentials = ""
    @State private var isConnected = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            QRConnectSection(
                providerName: "Claude",
                command: "curl -fsSL https://raw.githubusercontent.com/ApexAspire/ApexGauge/main/Scripts/qr-connect.swift -o /tmp/qr-connect.swift && swift /tmp/qr-connect.swift claude",
                clonedRepoCommand: "swift Scripts/qr-connect.swift claude",
                onPayload: handleScannedPayload
            )

            Section("Paste fallback") {
                Text("On your Mac: cat ~/.claude/.credentials.json, copy, paste here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $pastedCredentials)
                    .frame(minHeight: 130)
                    .font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()

                Button("Connect") {
                    Task { await connectPastedCredentials() }
                }
                .disabled(pastedCredentials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

                CredentialSecurityNote()
            }

            if isConnected {
                Section {
                    Button("Disconnect", role: .destructive) {
                        Task { await disconnect() }
                    }
                    .disabled(isWorking)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(statusIsError ? .red : .green)
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
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleScannedPayload(_ payload: ConnectPayload) {
        guard let credentials = payload.claudeCredentials else {
            statusIsError = true
            statusMessage = "That QR code is not for Claude. Scan the Claude connect code."
            return
        }
        Task { await save(credentials, successMessage: "Claude connected from QR.") }
    }

    private func connectPastedCredentials() async {
        guard let credentials = CredentialsParser.parseClaude(pastedCredentials) else {
            statusIsError = true
            statusMessage = "Could not find Claude credentials in that text. Paste the full credentials file or a refresh token."
            return
        }
        await save(credentials, successMessage: "Claude credentials saved securely.")
    }

    private func save(_ credentials: ClaudeCredentials, successMessage: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.saveClaude(credentials)
            pastedCredentials = ""
            isConnected = true
            statusIsError = false
            statusMessage = successMessage
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    private func disconnect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.clear(provider: .claude)
            pastedCredentials = ""
            isConnected = false
            statusIsError = false
            statusMessage = "Claude disconnected."
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }
}
