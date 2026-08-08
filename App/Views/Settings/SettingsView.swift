import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    let credentialStore: KeychainCredentialStore

    var body: some View {
        List {
            Section("Quota display") {
                Picker(
                    "Percentage mode",
                    selection: Binding(
                        get: { viewModel.displayPercentUsed },
                        set: { viewModel.setDisplayPercentUsed($0) }
                    )
                ) {
                    Text("% used").tag(true)
                    Text("% left").tag(false)
                }
                .pickerStyle(.segmented)

                Text("Applies to every quota shown on this iPhone and the paired Apple Watch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
