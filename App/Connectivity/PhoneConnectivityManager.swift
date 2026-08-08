import ApexGaugeCore
import Combine
import Foundation
import WatchConnectivity

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var lastPushDescription = "No watch push yet"

    /// Called for an explicit watch request. The handler refreshes and persists
    /// quotas before returning the encoded snapshot, or nil when it cannot.
    var snapshotRequestHandler: (@Sendable () async -> Data?)?

    private var session: WCSession?
    private let changeDetector: SnapshotChangeDetector?

    init(changeDetector: SnapshotChangeDetector? = nil) {
        self.changeDetector = changeDetector
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else {
            lastPushDescription = "WatchConnectivity unavailable"
            return
        }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    /// Attempts a transfer and reports whether one was actually queued/sent.
    /// Only requires an activated session: transfers queue for a paired watch
    /// even when the watch app was side-installed (devicectl) and
    /// isWatchAppInstalled reports false — gating on it silently drops data.
    @discardableResult
    func push(_ snapshot: UsageSnapshot) -> Bool {
        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            lastPushDescription = "Snapshot encoding failed: \(error.localizedDescription)"
            return false
        }

        return pushEncodedSnapshot(data)
    }

    /// Queues both complication info (while budget remains) and the latest
    /// application context. The latter is the durable fallback if the watch
    /// becomes unreachable before an immediate reply arrives.
    private func pushEncodedSnapshot(_ data: Data) -> Bool {
        guard let session else {
            lastPushDescription = "WatchConnectivity not activated"
            return false
        }

        guard session.activationState == .activated else {
            lastPushDescription = "WatchConnectivity not activated yet"
            return false
        }

        let payload = [ApexGaugeDefaults.watchSnapshotPayloadKey: data]
        var queuedComplicationTransfer = false
        if session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(payload)
            queuedComplicationTransfer = true
        }

        do {
            try session.updateApplicationContext(payload)
            if queuedComplicationTransfer {
                lastPushDescription = "complication push + application context (\(session.remainingComplicationUserInfoTransfers) transfers left)"
            } else {
                lastPushDescription = "application context"
            }
            return true
        } catch {
            if queuedComplicationTransfer {
                lastPushDescription = "complication push; application context failed: \(error.localizedDescription)"
                return true
            }
            lastPushDescription = "Application context failed: \(error.localizedDescription)"
            return false
        }
    }

    private func handleSnapshotRequest(
        replyHandler: (([String: Any]) -> Void)?
    ) async {
        guard let snapshotRequestHandler,
              let data = await snapshotRequestHandler()
        else {
            replyHandler?([:])
            return
        }

        // Explicit requests always transfer, regardless of the change detector.
        // The detector is updated only after at least one transport succeeded.
        if pushEncodedSnapshot(data),
           let snapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        {
            try? changeDetector?.recordPush(snapshot)
        }

        replyHandler?([ApexGaugeDefaults.watchSnapshotPayloadKey: data])
    }

    func pushDisplayMode(percentUsed: Bool) {
        guard let session else {
            lastPushDescription = "WatchConnectivity not activated"
            return
        }

        guard session.activationState == .activated,
              session.isPaired,
              session.isWatchAppInstalled
        else {
            lastPushDescription = "Paired watch app unavailable"
            return
        }

        do {
            try session.updateApplicationContext([
                ApexGaugeDefaults.watchDisplayModePayloadKey: percentUsed,
            ])
            lastPushDescription = "display mode application context"
        } catch {
            lastPushDescription = "Display mode context failed: \(error.localizedDescription)"
        }
    }

    func pushComplicationWindows(
        _ prefs: [ProviderSnapshot.Provider: ComplicationWindowChoice],
        hidden: Set<ProviderSnapshot.Provider>
    ) {
        guard let session, session.activationState == .activated,
              let data = ComplicationWindowPreferences.encode(prefs),
              let hiddenData = ComplicationWindowPreferences.encodeHidden(hidden)
        else {
            lastPushDescription = "WatchConnectivity not activated yet"
            return
        }

        do {
            try session.updateApplicationContext([
                ApexGaugeDefaults.complicationWindowsKey: data,
                ApexGaugeDefaults.complicationHiddenProvidersKey: hiddenData,
            ])
            lastPushDescription = "complication preferences sent"
        } catch {
            lastPushDescription = "Preference push failed: \(error.localizedDescription)"
        }
    }

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            if let error {
                self?.lastPushDescription = "Activation failed: \(error.localizedDescription)"
            } else if activationState == .activated {
                self?.lastPushDescription = "WatchConnectivity activated"
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.lastPushDescription = "WatchConnectivity inactive"
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
        Task { @MainActor [weak self] in
            self?.lastPushDescription = "WatchConnectivity reactivating"
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard message[ApexGaugeDefaults.watchSnapshotRequestKey] as? Bool == true else {
            return
        }

        Task { @MainActor [weak self] in
            await self?.handleSnapshotRequest(replyHandler: nil)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard message[ApexGaugeDefaults.watchSnapshotRequestKey] as? Bool == true else {
            replyHandler([:])
            return
        }

        let replyBox = ReplyHandlerBox(replyHandler)
        Task { @MainActor [weak self] in
            guard let self else {
                replyBox.handler([:])
                return
            }
            await self.handleSnapshotRequest(replyHandler: replyBox.handler)
        }
    }

    private final class ReplyHandlerBox: @unchecked Sendable {
        let handler: ([String: Any]) -> Void

        init(_ handler: @escaping ([String: Any]) -> Void) {
            self.handler = handler
        }
    }
}
