import ApexGaugeCore
import Combine
import Foundation
import WatchConnectivity

@MainActor
final class PhoneConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var lastPushDescription = "No watch push yet"

    private var session: WCSession?

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

    func push(_ snapshot: UsageSnapshot) {
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

        let data: Data
        do {
            data = try JSONEncoder().encode(snapshot)
        } catch {
            lastPushDescription = "Snapshot encoding failed: \(error.localizedDescription)"
            return
        }

        let payload = [ApexGaugeDefaults.watchSnapshotPayloadKey: data]
        if session.remainingComplicationUserInfoTransfers > 0 {
            session.transferCurrentComplicationUserInfo(payload)
            lastPushDescription = "complication push (\(session.remainingComplicationUserInfoTransfers) transfers left)"
            return
        }

        do {
            try session.updateApplicationContext(payload)
            lastPushDescription = "application context"
        } catch {
            lastPushDescription = "Application context failed: \(error.localizedDescription)"
        }
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
}
