import ApexGaugeCore
import Combine
import Foundation
import WatchConnectivity
import WidgetKit

@MainActor
final class SnapshotRequester: NSObject, ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var displayPercentUsed: Bool
    @Published private(set) var persistenceError: String?

    private let snapshotStore: WatchSnapshotStore
    private let sharedDefaults: UserDefaults?
    private var isActivated = false
    private var hasPendingSnapshotRequest = false
    private var isSnapshotRequestInFlight = false

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

    /// Requests a fresh phone-side fetch only when the shared cache is missing
    /// or more than one-third of the rendered stale threshold old (~15 min).
    func requestSnapshotIfStale() async {
        guard !isSnapshotRequestInFlight else { return }

        let persistedSnapshot: UsageSnapshot?
        do {
            persistedSnapshot = try await snapshotStore.load()
            snapshot = persistedSnapshot
            persistenceError = nil
        } catch {
            persistedSnapshot = snapshot
            persistenceError = error.localizedDescription
        }

        guard Self.needsRefresh(persistedSnapshot) else {
            return
        }

        hasPendingSnapshotRequest = true
        activate()
        sendPendingSnapshotRequestIfPossible()
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

    private static func needsRefresh(_ snapshot: UsageSnapshot?, now: Date = Date()) -> Bool {
        guard let oldestFetchedAt = snapshot?.providers.map(\.fetchedAt).min() else {
            return true
        }
        return now.timeIntervalSince(oldestFetchedAt) > ApexGaugeDefaults.staleAfter / 3
    }

    private func sendPendingSnapshotRequestIfPossible() {
        guard hasPendingSnapshotRequest else { return }

        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // Stay pending while unreachable. Clearing the flag here used to drop
        // the request permanently, so a watch that woke a moment before the
        // phone became reachable waited for the next foreground or timeline
        // cycle rather than for reachability itself.
        guard session.isReachable else {
            return
        }
        hasPendingSnapshotRequest = false
        isSnapshotRequestInFlight = true

        session.sendMessage(
            [ApexGaugeDefaults.watchSnapshotRequestKey: true],
            replyHandler: { [weak self] payload in
                self?.receivePayload(payload)
                Task { @MainActor [weak self] in
                    self?.isSnapshotRequestInFlight = false
                }
            },
            errorHandler: { [weak self] _ in
                // Cached data remains visible; the next foreground/timeline
                // budget cycle will retry if it is still stale.
                Task { @MainActor [weak self] in
                    self?.isSnapshotRequestInFlight = false
                }
            }
        )
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

        if let data = payload[ApexGaugeDefaults.complicationWindowsKey] as? Data {
            Task { @MainActor [weak self] in
                self?.receive(complicationWindows: data)
            }
        }

        if let data = payload[ApexGaugeDefaults.complicationHiddenProvidersKey] as? Data {
            Task { @MainActor [weak self] in
                self?.receive(complicationHiddenProviders: data)
            }
        }
    }

    private func receive(complicationHiddenProviders data: Data) {
        sharedDefaults?.set(data, forKey: ApexGaugeDefaults.complicationHiddenProvidersKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func receive(complicationWindows data: Data) {
        sharedDefaults?.set(data, forKey: ApexGaugeDefaults.complicationWindowsKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension SnapshotRequester: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated, error == nil else { return }
        Task { @MainActor [weak self] in
            self?.sendPendingSnapshotRequestIfPossible()
        }
    }

    /// The retry that makes a pending request meaningful: flush it the instant
    /// the phone becomes reachable instead of waiting for the next cycle.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.sendPendingSnapshotRequestIfPossible()
        }
    }

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
