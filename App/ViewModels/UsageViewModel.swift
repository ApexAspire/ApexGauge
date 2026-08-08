import ApexGaugeCore
import Combine
import Foundation

@MainActor
final class UsageViewModel: ObservableObject {
    static let useMockDataKey = "UseMockData"

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var persistenceError: String?
    @Published private(set) var useMockData: Bool
    @Published private(set) var displayPercentUsed: Bool

    private let mockEngine: any UsageEngineing
    private let liveEngine: any UsageEngineing
    private let snapshotStore: SnapshotStore
    private let connectivity: PhoneConnectivityManager?
    private let changeDetector: SnapshotChangeDetector?
    private let defaults: UserDefaults

    init(
        mockEngine: any UsageEngineing,
        liveEngine: any UsageEngineing,
        snapshotStore: SnapshotStore,
        connectivity: PhoneConnectivityManager? = nil,
        changeDetector: SnapshotChangeDetector? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.mockEngine = mockEngine
        self.liveEngine = liveEngine
        self.snapshotStore = snapshotStore
        self.connectivity = connectivity
        self.changeDetector = changeDetector
        self.defaults = defaults
        useMockData = defaults.object(forKey: Self.useMockDataKey) as? Bool ?? true
        displayPercentUsed = defaults.object(forKey: ApexGaugeDefaults.displayPercentUsedKey) as? Bool ?? true
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

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        persistenceError = nil
        defer { isRefreshing = false }

        let engine = useMockData ? mockEngine : liveEngine
        let refreshedSnapshot = await engine.refreshAll()

        do {
            try await snapshotStore.save(refreshedSnapshot)
        } catch {
            persistenceError = error.localizedDescription
        }
        snapshot = refreshedSnapshot

        // Push live snapshots to the watch when values moved (complication
        // transfers are budgeted — the detector decides).
        if !useMockData, let connectivity, let changeDetector,
           (try? changeDetector.shouldPush(refreshedSnapshot)) == true
        {
            connectivity.push(refreshedSnapshot)
        }
    }
}
