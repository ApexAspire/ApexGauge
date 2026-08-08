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

    private let mockEngine: any UsageEngineing
    private let liveEngine: any UsageEngineing
    private let snapshotStore: SnapshotStore
    private let defaults: UserDefaults

    init(
        mockEngine: any UsageEngineing,
        liveEngine: any UsageEngineing,
        snapshotStore: SnapshotStore,
        defaults: UserDefaults = .standard
    ) {
        self.mockEngine = mockEngine
        self.liveEngine = liveEngine
        self.snapshotStore = snapshotStore
        self.defaults = defaults
        useMockData = defaults.object(forKey: Self.useMockDataKey) as? Bool ?? true
    }

    func setUseMockData(_ enabled: Bool) {
        useMockData = enabled
        defaults.set(enabled, forKey: Self.useMockDataKey)
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
    }
}
