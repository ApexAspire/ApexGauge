import ApexGaugeCore
import Combine
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    nonisolated static let useMockDataKey = "UseMockData"
    nonisolated static let displayResetCountdownKey = "DisplayResetCountdown"

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var persistenceError: String?
    @Published private(set) var useMockData: Bool
    @Published private(set) var displayPercentUsed: Bool
    @Published private(set) var displayResetCountdown: Bool
    @Published private(set) var complicationWindows: [ProviderSnapshot.Provider: ComplicationWindowChoice]
    @Published private(set) var complicationHiddenProviders: Set<ProviderSnapshot.Provider>
    @Published private(set) var providerStatusReport: ProviderStatusReport?
    @Published private var refreshingProviderIDs: Set<String> = []

    private let mockEngine: any UsageEngineing
    private let liveEngine: any UsageEngineing
    private let liveFetchers: [any UsageFetching]
    private let snapshotStore: SnapshotStore
    private let connectivity: PhoneConnectivityManager?
    private let changeDetector: SnapshotChangeDetector?
    private let defaults: UserDefaults
    private let providerStatusFetcher: ProviderStatusFetcher

    init(
        mockEngine: any UsageEngineing,
        liveEngine: any UsageEngineing,
        liveFetchers: [any UsageFetching],
        snapshotStore: SnapshotStore,
        connectivity: PhoneConnectivityManager? = nil,
        changeDetector: SnapshotChangeDetector? = nil,
        defaults: UserDefaults = .standard,
        providerStatusFetcher: ProviderStatusFetcher? = nil
    ) {
        self.mockEngine = mockEngine
        self.liveEngine = liveEngine
        self.liveFetchers = liveFetchers
        self.snapshotStore = snapshotStore
        self.connectivity = connectivity
        self.changeDetector = changeDetector
        self.defaults = defaults
        self.providerStatusFetcher = providerStatusFetcher ?? ProviderStatusFetcher(defaults: defaults)
        useMockData = defaults.object(forKey: Self.useMockDataKey) as? Bool ?? true
        displayPercentUsed = defaults.object(forKey: ApexGaugeDefaults.displayPercentUsedKey) as? Bool ?? true
        displayResetCountdown = defaults.object(forKey: Self.displayResetCountdownKey) as? Bool ?? false
        complicationWindows = ComplicationWindowPreferences.decode(from: defaults)
        complicationHiddenProviders = ComplicationWindowPreferences.decodeHidden(from: defaults)
        providerStatusReport = nil
    }

    func setComplicationWindow(
        _ choice: ComplicationWindowChoice,
        for provider: ProviderSnapshot.Provider
    ) {
        var updated = complicationWindows
        updated[provider] = choice
        complicationWindows = updated
        ComplicationWindowPreferences.store(updated, in: defaults)
        connectivity?.pushComplicationWindows(updated, hidden: complicationHiddenProviders)
    }

    func setComplicationProviderHidden(_ hidden: Bool, provider: ProviderSnapshot.Provider) {
        var updated = complicationHiddenProviders
        if hidden {
            updated.insert(provider)
        } else {
            updated.remove(provider)
        }
        complicationHiddenProviders = updated
        ComplicationWindowPreferences.storeHidden(updated, in: defaults)
        connectivity?.pushComplicationWindows(complicationWindows, hidden: updated)
    }

    func setUseMockData(_ enabled: Bool) {
        useMockData = enabled
        defaults.set(enabled, forKey: Self.useMockDataKey)
    }

    func setDisplayPercentUsed(_ enabled: Bool) {
        displayPercentUsed = enabled
        defaults.set(enabled, forKey: ApexGaugeDefaults.displayPercentUsedKey)
        connectivity?.pushDisplayMode(percentUsed: enabled)

        // A mode change must re-render the watch immediately even when the
        // quota values themselves have not moved.
        if let snapshot {
            connectivity?.push(snapshot)
        }
    }

    func setDisplayResetCountdown(_ enabled: Bool) {
        displayResetCountdown = enabled
        defaults.set(enabled, forKey: Self.displayResetCountdownKey)
    }

    var isRefreshingAnyProvider: Bool {
        !refreshingProviderIDs.isEmpty
    }

    func isRefreshing(provider: ProviderSnapshot.Provider) -> Bool {
        refreshingProviderIDs.contains(provider.rawValue)
    }

    func status(for provider: ProviderSnapshot.Provider) -> ProviderStatus? {
        providerStatusReport?.status(for: provider)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        persistenceError = nil
        defer { isRefreshing = false }

        let engine = useMockData ? mockEngine : liveEngine
        let refreshedSnapshot = await engine.refreshAll()

        await persistAndPublish(refreshedSnapshot, pushToWatch: !useMockData)
        providerStatusReport = await providerStatusFetcher.fetch()
    }

    func refresh(provider: ProviderSnapshot.Provider) async {
        let providerID = provider.rawValue
        guard !isRefreshing, !refreshingProviderIDs.contains(providerID) else { return }

        refreshingProviderIDs.insert(providerID)
        persistenceError = nil
        let refreshesMockData = useMockData
        defer { refreshingProviderIDs.remove(providerID) }

        let refreshedProvider: ProviderSnapshot
        if refreshesMockData {
            let mockSnapshot = await mockEngine.refreshAll()
            guard let providerSnapshot = mockSnapshot.providers.first(where: { $0.provider == provider }) else {
                return
            }
            refreshedProvider = providerSnapshot
        } else if let fetcher = liveFetchers.first(where: { $0.provider == provider }) {
            do {
                refreshedProvider = try await fetcher.fetchUsage()
            } catch {
                refreshedProvider = failedProviderSnapshot(provider: provider, error: error)
            }
        } else {
            refreshedProvider = failedProviderSnapshot(
                provider: provider,
                message: "Provider refresh is unavailable."
            )
        }

        // If the data mode changed while the fetch was in flight, its result no
        // longer belongs in the currently displayed snapshot.
        guard refreshesMockData == useMockData else { return }

        var updatedSnapshot = snapshot ?? UsageSnapshot(providers: [])
        if let index = updatedSnapshot.providers.firstIndex(where: { $0.provider == provider }) {
            updatedSnapshot.providers[index] = refreshedProvider
        } else {
            updatedSnapshot.providers.append(refreshedProvider)
        }

        await persistAndPublish(updatedSnapshot, pushToWatch: !refreshesMockData)
    }

    private func persistAndPublish(_ refreshedSnapshot: UsageSnapshot, pushToWatch: Bool) async {

        do {
            try await snapshotStore.save(refreshedSnapshot)
        } catch {
            persistenceError = error.localizedDescription
        }
        snapshot = refreshedSnapshot

        // Push live snapshots to the watch when values moved (complication
        // transfers are budgeted — the detector decides). Only record the push
        // after a confirmed send so a failed transfer is retried next refresh.
        if pushToWatch, let connectivity, let changeDetector,
           changeDetector.shouldPush(refreshedSnapshot),
           connectivity.push(refreshedSnapshot)
        {
            try? changeDetector.recordPush(refreshedSnapshot)
        }
    }

    private func failedProviderSnapshot(
        provider: ProviderSnapshot.Provider,
        error: Error
    ) -> ProviderSnapshot {
        failedProviderSnapshot(provider: provider, message: Self.errorMessage(error))
    }

    private func failedProviderSnapshot(
        provider: ProviderSnapshot.Provider,
        message: String
    ) -> ProviderSnapshot {
        if var existing = snapshot?.providers.first(where: { $0.provider == provider }) {
            existing.lastError = message
            return existing
        }

        return ProviderSnapshot(
            provider: provider,
            windows: [],
            fetchedAt: Date(),
            lastError: message
        )
    }

    private static func errorMessage(_ error: Error) -> String {
        guard let error = error as? UsageFetchError else {
            return error.localizedDescription
        }

        switch error {
        case .notConfigured:
            return "Not configured"
        case .unauthorized:
            return "Unauthorized"
        case let .rateLimited(retryAfter):
            return retryAfter.map { "Rate limited; retry after \($0) seconds" } ?? "Rate limited"
        case let .http(status, body):
            return "HTTP \(status): \(body)"
        case let .decoding(message):
            return "Could not decode provider response: \(message)"
        case let .network(message):
            return "Network error: \(message)"
        }
    }
}
