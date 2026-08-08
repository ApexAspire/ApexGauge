import ApexGaugeCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    let credentialStore: KeychainCredentialStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: ApexTheme.Spacing.standard) {
                    dashboardHeader

                    Toggle(
                        isOn: Binding(
                            get: { viewModel.displayResetCountdown },
                            set: { viewModel.setDisplayResetCountdown($0) }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: ApexTheme.Spacing.xSmall) {
                            Label("Reset countdown", systemImage: "timer")
                                .font(ApexTheme.Typography.label)
                                .foregroundStyle(ApexTheme.Colors.inkPrimary)
                            Text("Show the time remaining instead of the reset date.")
                                .font(ApexTheme.Typography.caption)
                                .foregroundStyle(ApexTheme.Colors.inkSecondary)
                        }
                    }
                    .tint(ApexTheme.Colors.accent)
                    .padding(ApexTheme.Spacing.standard)
                    .apexSurface(cornerRadius: ApexTheme.Radius.innerCard, elevated: false)

                    if let persistenceError = viewModel.persistenceError {
                        ErrorBannerView(message: "Snapshot could not be saved: \(persistenceError)")
                    }

                    if let snapshot = viewModel.snapshot {
                        ForEach(snapshot.providers, id: \.provider) { provider in
                            ProviderCardView(
                                snapshot: provider,
                                displayPercentUsed: viewModel.displayPercentUsed,
                                displayResetCountdown: viewModel.displayResetCountdown,
                                isRefreshing: viewModel.isRefreshing(provider: provider.provider),
                                refreshDisabled: viewModel.isRefreshing,
                                onRefresh: {
                                    Task { await viewModel.refresh(provider: provider.provider) }
                                }
                            )
                        }
                    } else {
                        ProgressView("Loading quota data…")
                            .font(ApexTheme.Typography.body)
                            .foregroundStyle(ApexTheme.Colors.inkSecondary)
                            .tint(ApexTheme.Colors.accent)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding(.horizontal, ApexTheme.Spacing.standard)
                .padding(.vertical, ApexTheme.Spacing.large)
            }
            .background(ApexTheme.Colors.background)
            .navigationTitle("Apex Gauge")
            .navigationBarTitleDisplayMode(.inline)
            .tint(ApexTheme.Colors.accent)
            .toolbarBackground(ApexTheme.Colors.surface.opacity(0.96), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView(credentialStore: credentialStore)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        if viewModel.isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(viewModel.isRefreshing || viewModel.isRefreshingAnyProvider)
                }
            }
            .refreshable {
                await viewModel.refresh()
            }
            .task {
                if viewModel.snapshot == nil {
                    await viewModel.refresh()
                }
            }
        }
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: ApexTheme.Spacing.small) {
            HStack(spacing: ApexTheme.Spacing.small) {
                Rectangle()
                    .fill(ApexTheme.Colors.inkTertiary)
                    .frame(width: 24, height: 1)
                Text("Usage overview")
                    .font(ApexTheme.Typography.eyebrow)
                    .textCase(.uppercase)
                    .tracking(1.2)
            }
            .foregroundStyle(ApexTheme.Colors.inkTertiary)

            Text("Quota position")
                .font(ApexTheme.Typography.displayLarge)
                .foregroundStyle(ApexTheme.Colors.inkPrimary)
                .accessibilityAddTraits(.isHeader)

            Text("Current allowance across each connected provider.")
                .font(ApexTheme.Typography.body)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
