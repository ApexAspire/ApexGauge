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
            Section("Before you connect") {
                Text("Apex Gauge is unofficial and is not affiliated with Anthropic. It reads your usage through an undocumented provider endpoint using your own account credentials, which may stop working or carry account risk. Your token never leaves this device except when sent to Anthropic.")
                    .font(ApexTheme.Typography.caption)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)
            }
            .apexListRow()

            QRConnectSection(
                providerName: "Claude",
                command: "git clone --depth 1 https://github.com/ApexAspire/ApexGauge.git && cd ApexGauge && swift Scripts/qr-connect.swift claude",
                clonedRepoCommand: "swift Scripts/qr-connect.swift claude",
                onPayload: handleScannedPayload
            )

            Section("Paste fallback") {
                Text("On your Mac, copy the contents of `~/.claude/.credentials.json` and paste them here.")
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
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
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
