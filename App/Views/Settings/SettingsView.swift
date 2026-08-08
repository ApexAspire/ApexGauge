import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    let credentialStore: KeychainCredentialStore

    var body: some View {
        List {
            Section("Data") {
                Toggle(
                    "Use Mock Data",
                    isOn: Binding(
                        get: { viewModel.useMockData },
                        set: { viewModel.setUseMockData($0) }
                    )
                )

                Text(
                    viewModel.useMockData
                        ? "Shows realistic preview quotas without contacting providers."
                        : "Live fetching will become available when the provider engine is integrated."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Providers") {
                NavigationLink("Claude") {
                    ClaudeSettingsView(credentialStore: credentialStore)
                }
                NavigationLink("Codex / ChatGPT") {
                    CodexSettingsView(credentialStore: credentialStore)
                }
                NavigationLink("Kimi") {
                    KimiSettingsView(credentialStore: credentialStore)
                }
            }
        }
        .navigationTitle("Settings")
        .onChange(of: viewModel.useMockData) {
            Task { await viewModel.refresh() }
        }
    }
}
