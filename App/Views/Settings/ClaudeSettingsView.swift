import ApexGaugeCore
import SwiftUI

struct ClaudeSettingsView: View {
    let credentialStore: KeychainCredentialStore

    @AppStorage(ClaudeSource.preferenceKey) private var sourceRaw = ClaudeSource.default.rawValue

    @State private var bridgeStatus: String?
    @State private var pastedCredentials = ""
    @State private var isConnected = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var source: ClaudeSource {
        ClaudeSource(rawValue: sourceRaw) ?? .default
    }

    var body: some View {
        Form {
            Section("Usage source") {
                Picker("Source", selection: $sourceRaw) {
                    ForEach(ClaudeSource.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(
                    source == .bridge
                        ? "Claude Code reports your 5-hour and weekly usage to its own status line on the Mac. The bridge captures it there and relays it through your iCloud account — no Claude credentials are stored on this iPhone."
                        : "Reads your usage directly from Anthropic using your subscription token stored on this iPhone."
                )
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)
            }
            .apexListRow()

            if source == .bridge {
                bridgeSection
            } else {
                oauthSections
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
        .task {
            await loadConnectionState()
            await loadBridgeStatus()
        }
    }

    @ViewBuilder
    private var bridgeSection: some View {
        Section("Bridge status") {
            LabeledContent("State", value: bridgeStatus ?? "Checking…")

            Text("Setup is only complete once this reads “receiving”. If it says iCloud is unavailable, sign in to iCloud on this iPhone and turn on iCloud Drive.")
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)
        }
        .apexListRow()

        Section("Set up the Mac bridge") {
            Text("On the Mac where you run Claude Code:")
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)

            Text("./Scripts/build-apexgauge-bridge.sh\n./dist/apexgauge-bridge install")
                .font(ApexTheme.Typography.mono)
                .textSelection(.enabled)

            Text("The bridge adds a Claude Code status line entry and a login item that publishes to iCloud. Any status line you already use keeps working. Both devices must be signed in to the same Apple ID with iCloud Drive on.")
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)

            Text("Figures update while Claude Code is running, and only on Pro and Max plans. This path reports the 5-hour and weekly windows; the per-model Opus, Sonnet, and Fable windows are not available here.")
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)
        }
        .apexListRow()
    }

    @ViewBuilder
    private var oauthSections: some View {
        Section("Anthropic's policy on this path") {
            Text("This is not an official method and appears nowhere in Anthropic's documentation. Anthropic reserves subscription OAuth tokens for Claude Code and its own apps, and directs third-party developers to API keys instead. That restriction is aimed at third-party coding tools that route Claude requests through a subscription; Apex Gauge only reads usage figures and sends no prompts. Anthropic may nonetheless treat this as third-party use, and may block the token or act on the account without notice. Use entirely at your own risk.")
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.warning)
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
    }

    /// Distinguishes the three setup states a user can actually be in, because
    /// "no Claude data" otherwise looks identical whether iCloud is signed out,
    /// the Mac half was never installed, or Claude Code simply has not run.
    private func loadBridgeStatus() async {
        let status = await Task.detached(priority: .userInitiated) { () -> String in
            // Same read the dashboard uses, so Settings and the card cannot disagree.
            switch try? ClaudeBridgeFetcher().read() {
            case let .unavailable(state):
                return state.title
            case let .available(snapshot):
                let minutes = Int(Date().timeIntervalSince(snapshot.capturedAt) / 60)
                return minutes < 1 ? "Receiving (just now)" : "Receiving (\(minutes)m ago)"
            case nil:
                return "Bridge file unreadable"
            }
        }.value

        bridgeStatus = status
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
