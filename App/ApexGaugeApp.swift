import ApexGaugeCore
import SwiftUI

@main
struct ApexGaugeApp: App {
    @StateObject private var viewModel: UsageViewModel
    private let credentialStore: KeychainCredentialStore
    private let connectivity: PhoneConnectivityManager

    init() {
        UserDefaults.standard.register(defaults: [UsageViewModel.useMockDataKey: true])

        let credentialStore = KeychainCredentialStore()
        self.credentialStore = credentialStore
        let liveEngine = UsageEngine(
            claude: ClaudeUsageFetcher(store: credentialStore),
            codex: CodexUsageFetcher(store: credentialStore),
            kimi: KimiUsageFetcher(store: credentialStore)
        )
        let snapshotStore = SnapshotStore()
        let connectivity = PhoneConnectivityManager()
        self.connectivity = connectivity
        connectivity.activate()

        // Background refresh: re-fetch quotas, persist, and push to the watch.
        let changeDetector = SnapshotChangeDetector()
        RefreshScheduler.register {
            let snapshot = await liveEngine.refreshAll()
            try? await snapshotStore.save(snapshot)
            if (try? changeDetector.shouldPush(snapshot)) == true {
                await connectivity.push(snapshot)
            }
        }
        RefreshScheduler.scheduleNext()

        _viewModel = StateObject(
            wrappedValue: UsageViewModel(
                mockEngine: MockUsageEngine(),
                liveEngine: liveEngine,
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
        }
    }
}
