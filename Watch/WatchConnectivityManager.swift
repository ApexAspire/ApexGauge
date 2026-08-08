import ApexGaugeCore
import Combine
import Foundation
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var displayPercentUsed: Bool
    @Published private(set) var persistenceError: String?

    private let snapshotStore: WatchSnapshotStore
    private let sharedDefaults: UserDefaults?
    private var isActivated = false

    init(
        snapshotStore: WatchSnapshotStore = WatchSnapshotStore(),
        sharedDefaults: UserDefaults? = UserDefaults(suiteName: ApexGaugeDefaults.appGroupID)
    ) {
        self.snapshotStore = snapshotStore
        self.sharedDefaults = sharedDefaults
        displayPercentUsed = sharedDefaults?.object(
            forKey: ApexGaugeDefaults.displayPercentUsedKey
        ) as? Bool ?? true
        super.init()

        Task { [weak self] in
            await self?.loadPersistedSnapshot()
        }
    }

    func activate() {
        guard WCSession.isSupported(), !isActivated else {
            return
        }

        isActivated = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    private func loadPersistedSnapshot() async {
        do {
            snapshot = try await snapshotStore.load()
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func receive(_ snapshot: UsageSnapshot) async {
        do {
            try await snapshotStore.save(snapshot)
            self.snapshot = snapshot
            persistenceError = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            persistenceError = error.localizedDescription
        }
    }

    private func receive(displayPercentUsed: Bool) {
        sharedDefaults?.set(displayPercentUsed, forKey: ApexGaugeDefaults.displayPercentUsedKey)
        self.displayPercentUsed = displayPercentUsed
        WidgetCenter.shared.reloadAllTimelines()
    }

    nonisolated private func receivePayload(_ payload: [String: Any]) {
        if let data = payload[ApexGaugeDefaults.watchSnapshotPayloadKey] as? Data,
           let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data) {
            Task { @MainActor [weak self] in
                await self?.receive(snapshot)
            }
        }

        if let displayPercentUsed = payload[ApexGaugeDefaults.watchDisplayModePayloadKey] as? Bool {
            Task { @MainActor [weak self] in
                self?.receive(displayPercentUsed: displayPercentUsed)
            }
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {}

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receivePayload(userInfo)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        receivePayload(applicationContext)
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
