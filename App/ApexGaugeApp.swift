import SwiftUI

@main
struct ApexGaugeApp: App {
    @StateObject private var viewModel: UsageViewModel
    private let credentialStore: KeychainCredentialStore

    init() {
        UserDefaults.standard.register(defaults: [UsageViewModel.useMockDataKey: true])

        let credentialStore = KeychainCredentialStore()
        self.credentialStore = credentialStore
        _viewModel = StateObject(
            wrappedValue: UsageViewModel(
                mockEngine: MockUsageEngine(),
                liveEngine: UnavailableUsageEngine(),
                snapshotStore: SnapshotStore()
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(credentialStore: credentialStore)
                .environmentObject(viewModel)
        }
    }
}
