import ApexGaugeCore
import SwiftUI

struct CodexSettingsView: View {
    let credentialStore: KeychainCredentialStore

    @State private var pastedCredentials = ""
    @State private var isConnected = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            QRConnectSection(
                providerName: "Codex",
                command: "curl -fsSL https://raw.githubusercontent.com/ApexAspire/ApexGauge/main/Scripts/qr-connect.swift -o /tmp/qr-connect.swift && swift /tmp/qr-connect.swift codex",
                clonedRepoCommand: "swift Scripts/qr-connect.swift codex",
                onPayload: handleScannedPayload
            )

            Section("Paste fallback") {
                Text("On your Mac: cat ~/.codex/auth.json, copy, paste here.")
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

            Section {
                Text("After connecting here, this phone becomes the refresh owner — avoid signing in/out of the Codex CLI on the Mac, or re-paste if Codex stops updating.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
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
        .navigationTitle("Codex")
        .task { await loadConnectionState() }
    }

    private func loadConnectionState() async {
        do {
            isConnected = try await credentialStore.loadCodex() != nil
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    @MainActor
    private func handleScannedPayload(_ payload: ConnectPayload) {
        guard let credentials = payload.codexCredentials else {
            statusIsError = true
            statusMessage = "That QR code is not for Codex. Scan the Codex connect code."
            return
        }
        Task { await save(credentials, successMessage: "Codex connected from QR.") }
    }

    private func connectPastedCredentials() async {
        guard let credentials = CredentialsParser.parseCodex(pastedCredentials) else {
            statusIsError = true
            statusMessage = "Could not find Codex credentials in that text. Paste the full auth file or labelled token lines."
            return
        }
        await save(credentials, successMessage: "Codex credentials saved securely.")
    }

    private func save(_ credentials: CodexCredentials, successMessage: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.saveCodex(credentials)
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
            try await credentialStore.clear(provider: .codex)
            pastedCredentials = ""
            isConnected = false
            statusIsError = false
            statusMessage = "Codex disconnected."
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }
}
