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
            Section("Before you connect") {
                Text("Apex Gauge is unofficial and is not affiliated with OpenAI. It reads your usage through an undocumented provider endpoint using your own account credentials, which may stop working or carry account risk. Your token never leaves this device except when sent to OpenAI.")
                    .font(ApexTheme.Typography.caption)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)
            }
            .apexListRow()

            QRConnectSection(
                providerName: "Codex",
                command: "curl -fsSL https://raw.githubusercontent.com/ApexAspire/ApexGauge/main/Scripts/qr-connect.swift -o /tmp/qr-connect.swift && swift /tmp/qr-connect.swift codex",
                clonedRepoCommand: "swift Scripts/qr-connect.swift codex",
                onPayload: handleScannedPayload
            )

            Section("Paste fallback") {
                Text("On your Mac, copy the contents of `~/.codex/auth.json` and paste them here.")
                    .font(ApexTheme.Typography.caption)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)

                TextEditor(text: $pastedCredentials)
                    .frame(minHeight: 130)
                    .font(ApexTheme.Typography.mono)
                    .scrollContentBackground(.hidden)
                    .padding(ApexTheme.Spacing.small)
                    .background(
                        ApexTheme.Colors.surfaceRaised,
                        in: RoundedRectangle(
                            cornerRadius: ApexTheme.Radius.control,
                            style: .continuous
                        )
                    )
                    .overlay {
                        RoundedRectangle(
                            cornerRadius: ApexTheme.Radius.control,
                            style: .continuous
                        )
                        .stroke(ApexTheme.Colors.border, lineWidth: 1)
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .privacySensitive()

                Button("Connect") {
                    Task { await connectPastedCredentials() }
                }
                .disabled(pastedCredentials.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

                CredentialSecurityNote()
            }
            .apexListRow()

            Section {
                Label(
                    "This iPhone becomes the refresh owner. If Codex stops updating after a CLI sign-in change on your Mac, paste the credentials again.",
                    systemImage: "exclamationmark.circle"
                )
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.warning)
            }
            .apexListRow()

            if isConnected {
                Section {
                    Button("Disconnect", role: .destructive) {
                        Task { await disconnect() }
                    }
                    .disabled(isWorking)
                }
                .apexListRow()
            }

            if let statusMessage {
                Section {
                    Label(
                        statusMessage,
                        systemImage: statusIsError ? "exclamationmark.triangle" : "checkmark.circle"
                    )
                    .font(ApexTheme.Typography.compact)
                    .foregroundStyle(
                        statusIsError ? ApexTheme.Colors.danger : ApexTheme.Colors.success
                    )
                }
                .apexListRow()
            }
        }
        .font(ApexTheme.Typography.body)
        .apexFormStyle()
        .navigationTitle("Codex")
        .navigationBarTitleDisplayMode(.inline)
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
