import ApexGaugeCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    let credentialStore: KeychainCredentialStore

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 16) {
                    if let persistenceError = viewModel.persistenceError {
                        ErrorBannerView(message: "Snapshot could not be saved: \(persistenceError)")
                    }

                    if let snapshot = viewModel.snapshot {
                        ForEach(snapshot.providers, id: \.provider) { provider in
                            ProviderCardView(snapshot: provider)
                        }
                    } else {
                        ProgressView("Loading usage…")
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("ApexGauge")
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
                    .disabled(viewModel.isRefreshing)
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
}
