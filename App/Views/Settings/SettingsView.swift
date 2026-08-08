import ApexGaugeCore
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

            Section("Complication") {
                ForEach(ProviderSnapshot.Provider.allCases, id: \.self) { provider in
                    let isShown = !viewModel.complicationHiddenProviders.contains(provider)
                    HStack(spacing: ApexTheme.Spacing.small) {
                        Toggle(
                            isOn: Binding(
                                get: { isShown },
                                set: { viewModel.setComplicationProviderHidden(!$0, provider: provider) }
                            )
                        ) {
                            Label {
                                Text(provider.displayName)
                            } icon: {
                                Image(provider.rawValue)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(provider.brandTint)
                                    .frame(width: 16, height: 16)
                            }
                        }

                        if isShown {
                            Picker(
                                "Second bar",
                                selection: Binding(
                                    get: { viewModel.complicationWindows[provider] ?? .weekly },
                                    set: { viewModel.setComplicationWindow($0, for: provider) }
                                )
                            ) {
                                ForEach(ComplicationWindowChoice.allCases, id: \.self) { choice in
                                    Text(choice.displayName).tag(choice)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .fixedSize()
                        }
                    }
                }

                Text("Choose which providers appear on the watch complication, and each visible row's second bar (Session always leads). “Lowest” tracks whichever non-session window is closest to exhaustion.")
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

            Section("About") {
                if let privacyPolicyURL = URL(
                    string: "https://apexaspire.github.io/ApexGauge/app-store/privacy-policy"
                ) {
                    Link("Privacy Policy", destination: privacyPolicyURL)
                }

                if let supportURL = URL(
                    string: "https://apexaspire.github.io/ApexGauge/support"
                ) {
                    Link("Support", destination: supportURL)
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
