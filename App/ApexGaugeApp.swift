import ApexGaugeCore
import SwiftUI

@main
struct ApexGaugeApp: App {
    @StateObject private var viewModel: UsageViewModel
    private let credentialStore: KeychainCredentialStore
    private let connectivity: PhoneConnectivityManager

    init() {
        UserDefaults.standard.register(defaults: [
            UsageViewModel.useMockDataKey: true,
            ApexGaugeDefaults.displayPercentUsedKey: true,
            UsageViewModel.displayResetCountdownKey: false,
        ])

        let credentialStore = KeychainCredentialStore()
        self.credentialStore = credentialStore
        let claudeFetcher = ClaudeUsageFetcher(store: credentialStore)
        let codexFetcher = CodexUsageFetcher(store: credentialStore)
        let kimiFetcher = KimiUsageFetcher(store: credentialStore)
        let liveFetchers: [any UsageFetching] = [claudeFetcher, codexFetcher, kimiFetcher]
        let liveEngine = UsageEngine(claude: claudeFetcher, codex: codexFetcher, kimi: kimiFetcher)
        let snapshotStore = SnapshotStore()
        let connectivity = PhoneConnectivityManager()
        self.connectivity = connectivity
        connectivity.activate()

        // Background refresh: re-fetch quotas, persist, and push to the watch.
        let changeDetector = SnapshotChangeDetector()
        RefreshScheduler.register {
            let snapshot = await liveEngine.refreshAll()
            try? await snapshotStore.save(snapshot)
            if changeDetector.shouldPush(snapshot),
               await connectivity.push(snapshot)
            {
                try? changeDetector.recordPush(snapshot)
            }
        }
        RefreshScheduler.scheduleNext()

        _viewModel = StateObject(
            wrappedValue: UsageViewModel(
                mockEngine: MockUsageEngine(),
                liveEngine: liveEngine,
                liveFetchers: liveFetchers,
                snapshotStore: snapshotStore,
                connectivity: connectivity,
                changeDetector: changeDetector
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView(credentialStore: credentialStore)
                .environmentObject(viewModel)
                .environmentObject(connectivity)
        }
    }
}
