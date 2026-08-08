import ApexGaugeCore
import SwiftUI

@main
struct ApexGaugeApp: App {
    @StateObject private var viewModel: UsageViewModel
    private let credentialStore: KeychainCredentialStore

    init() {
        UserDefaults.standard.register(defaults: [UsageViewModel.useMockDataKey: true])

        let credentialStore = KeychainCredentialStore()
        self.credentialStore = credentialStore
        let liveEngine = UsageEngine(
            claude: ClaudeUsageFetcher(store: credentialStore),
            codex: CodexUsageFetcher(store: credentialStore),
            kimi: KimiUsageFetcher(store: credentialStore)
        )
        _viewModel = StateObject(
            wrappedValue: UsageViewModel(
                mockEngine: MockUsageEngine(),
                liveEngine: liveEngine,
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
