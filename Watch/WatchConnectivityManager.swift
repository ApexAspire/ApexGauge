import ApexGaugeCore
import Combine
import Foundation
import WatchConnectivity
import WidgetKit

@MainActor
final class WatchConnectivityManager: NSObject, ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var persistenceError: String?

    private let snapshotStore: WatchSnapshotStore
    private var isActivated = false

    init(snapshotStore: WatchSnapshotStore = WatchSnapshotStore()) {
        self.snapshotStore = snapshotStore
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

    nonisolated private func decodeSnapshot(from payload: [String: Any]) {
        guard let data = payload[ApexGaugeDefaults.watchSnapshotPayloadKey] as? Data,
              let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.receive(snapshot)
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
        decodeSnapshot(from: userInfo)
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        decodeSnapshot(from: applicationContext)
    }

#if os(iOS)
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
