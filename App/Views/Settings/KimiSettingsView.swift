import ApexGaugeCore
import SwiftUI

struct KimiSettingsView: View {
    let credentialStore: KeychainCredentialStore

    @State private var apiKey = ""
    @State private var isConnected = false
    @State private var isWorking = false
    @State private var statusMessage: String?
    @State private var statusIsError = false

    var body: some View {
        Form {
            Section("How to connect") {
                Text("Create an API key in the Kimi Code Console (https://www.kimi.com/code/console) and paste it here.")
                Link("Open Kimi Code Console", destination: URL(string: "https://www.kimi.com/code/console")!)
            }

            Section("API key") {
                SecureField("Kimi API key", text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                CredentialSecurityNote()
            }

            Section {
                Button("Connect") {
                    Task { await connect() }
                }
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

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
                        .foregroundStyle(statusIsError ? .red : .green)
                }
            }
        }
        .navigationTitle("Kimi")
        .task { await loadConnectionState() }
    }

    private func loadConnectionState() async {
        do {
            isConnected = try await credentialStore.loadKimi() != nil
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    private func connect() async {
        guard let credentials = CredentialsParser.parseKimi(apiKey) else {
            statusIsError = true
            statusMessage = "Paste a Kimi API key to connect."
            return
        }

        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.saveKimi(credentials)
            apiKey = ""
            isConnected = true
            statusIsError = false
            statusMessage = "Kimi credentials saved securely."
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }

    private func disconnect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.clear(provider: .kimi)
            apiKey = ""
            isConnected = false
            statusIsError = false
            statusMessage = "Kimi disconnected."
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
        }
    }
}
