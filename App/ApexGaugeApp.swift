import ApexGaugeCore
import Foundation
import SwiftUI

private enum RefreshInvocation {
    /// An explicit watch request owns its transfer and must not be filtered by
    /// the budgeted background change detector inside the shared pipeline.
    @TaskLocal static var isExplicitWatchRequest = false
}

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
            ClaudeSource.preferenceKey: ClaudeSource.default.rawValue,
        ])

        let credentialStore = KeychainCredentialStore()
        self.credentialStore = credentialStore
        let claudeFetcher = ClaudeRoutingFetcher(
            bridge: ClaudeBridgeFetcher(),
            oauth: ClaudeUsageFetcher(store: credentialStore))
        let codexFetcher = CodexUsageFetcher(store: credentialStore)
        let kimiFetcher = KimiUsageFetcher(store: credentialStore)
        let liveFetchers: [any UsageFetching] = [claudeFetcher, codexFetcher, kimiFetcher]
        let liveEngine = UsageEngine(claude: claudeFetcher, codex: codexFetcher, kimi: kimiFetcher)
        let snapshotStore = SnapshotStore()
        let changeDetector = SnapshotChangeDetector()
        let connectivity = PhoneConnectivityManager(changeDetector: changeDetector)
        self.connectivity = connectivity

        // Shared refresh pipeline for scheduled and watch-initiated refreshes.
        // Mock mode is a privacy promise ("without contacting providers"), so
        // background and watch-triggered paths must honour it too.
        let performRefresh: @Sendable () async -> UsageSnapshot = {
            let useMock = UserDefaults.standard.bool(forKey: UsageViewModel.useMockDataKey)
            let previousSnapshot = await snapshotStore.load()
            var snapshot = useMock
                ? await MockUsageEngine().refreshAll()
                : await liveEngine.refreshAll()
            snapshot.providers = snapshot.providers.map { provider in
                provider.carryingForward(from: previousSnapshot?.providers.first {
                    $0.provider == provider.provider
                })
            }
            try? await snapshotStore.save(snapshot)
            if !RefreshInvocation.isExplicitWatchRequest,
               changeDetector.shouldPush(snapshot),
               await connectivity.push(snapshot)
            {
                try? changeDetector.recordPush(snapshot)
            }
            return snapshot
        }

        // Install the background-launch request handler before activation, so
        // the first message cannot arrive without a refresh path ready.
        connectivity.snapshotRequestHandler = {
            let snapshot = await RefreshInvocation.$isExplicitWatchRequest.withValue(true) {
                await performRefresh()
            }
            return try? JSONEncoder().encode(snapshot)
        }
        connectivity.cachedSnapshotProvider = { await snapshotStore.load() }
        connectivity.activate()
        ICloudContainerWarmUp.run()

        RefreshScheduler.register {
            _ = await performRefresh()
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
