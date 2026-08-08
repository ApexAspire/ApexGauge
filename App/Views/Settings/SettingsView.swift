import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var connectivity: PhoneConnectivityManager
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
                    .font(ApexTheme.Typography.caption)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)
            }
            .apexListRow()

            Section("Data") {
                Toggle(
                    "Use mock data",
                    isOn: Binding(
                        get: { viewModel.useMockData },
                        set: { viewModel.setUseMockData($0) }
                    )
                )

                Text(
                    viewModel.useMockData
                        ? "Shows representative quotas without contacting providers."
                        : "Fetches current quotas using credentials stored on this iPhone."
                )
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)
            }
            .apexListRow()

            Section("Watch") {
                LabeledContent("Last push", value: connectivity.lastPushDescription)

                Text("Usage data reaches the watch over WatchConnectivity after each refresh. If the watch shows “waiting for iPhone”, pull to refresh on the dashboard and check this line.")
                    .font(ApexTheme.Typography.caption)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)
            }
            .apexListRow()

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
            .apexListRow()
        }
        .font(ApexTheme.Typography.body)
        .apexFormStyle()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: viewModel.useMockData) {
            Task { await viewModel.refresh() }
        }
    }
}
