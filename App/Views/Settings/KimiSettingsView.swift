import ApexGaugeCore
import SwiftUI

struct KimiSettingsView: View {
    let credentialStore: KeychainCredentialStore

    @State private var apiKey = ""
    @State private var isConnected = false
    @State private var isWorking = false
    @State private var statusMessage: String?

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
                        .foregroundStyle(isConnected ? .green : .red)
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
            statusMessage = error.localizedDescription
        }
    }

    private func connect() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await credentialStore.saveKimi(
                KimiCredentials(apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
            )
            apiKey = ""
            isConnected = true
            statusMessage = "Kimi credentials saved securely."
        } catch {
            isConnected = false
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
            statusMessage = "Kimi disconnected."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}
