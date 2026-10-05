import ApexGaugeCore
import Foundation
import WatchConnectivity
import WidgetKit

/// A lightweight extension-process requester. Timeline generation only starts
/// it; replies and opportunistic delegate deliveries persist asynchronously.
final class ComplicationSnapshotRequester: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = ComplicationSnapshotRequester()

    private let lock = NSLock()
    private var hasPendingRequest = false
    private var isRequestInFlight = false

    func requestSnapshot() {
        guard WCSession.isSupported() else { return }

        lock.lock()
        guard !hasPendingRequest, !isRequestInFlight else {
            lock.unlock()
            return
        }
        hasPendingRequest = true
        lock.unlock()

        let session = WCSession.default
        session.delegate = self
        if session.activationState == .activated {
            sendPendingRequestIfPossible(using: session)
        } else {
            session.activate()
        }
    }

    private func sendPendingRequestIfPossible(using session: WCSession) {
        guard session.activationState == .activated else { return }

        lock.lock()
        let shouldSend = hasPendingRequest && !isRequestInFlight && session.isReachable
        // Only consume the pending flag when the request is actually going out;
        // clearing it unconditionally discarded requests made while the phone
        // was briefly unreachable, with nothing left to retry.
        if shouldSend {
            hasPendingRequest = false
            isRequestInFlight = true
        }
        lock.unlock()

        guard shouldSend else { return }
        session.sendMessage(
            [ApexGaugeDefaults.watchSnapshotRequestKey: true],
            replyHandler: { [weak self] payload in
                self?.receivePayload(payload)
                self?.finishRequest()
            },
            errorHandler: { [weak self] _ in
                // The cached timeline stays valid; a later timeline cycle retries.
                self?.finishRequest()
            }
        )
    }

    private func finishRequest() {
        lock.lock()
        isRequestInFlight = false
        lock.unlock()
    }

    private func receivePayload(_ payload: [String: Any]) {
        // One reload per payload (budget: ~4 complication tasks/hour); the
        // decision logic lives in ApexGaugeCore so it is unit-tested.
        let defaults = UserDefaults(suiteName: ApexGaugeDefaults.appGroupID)
        ComplicationPayloadApplier.apply(
            payload,
            setData: { data, key in defaults?.set(data, forKey: key) },
            setBool: { value, key in defaults?.set(value, forKey: key) },
            writeSnapshot: { data in
                guard let containerURL = FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: ApexGaugeDefaults.appGroupID
                ) else { return false }
                let snapshotURL = containerURL.appendingPathComponent(ApexGaugeDefaults.snapshotFilename)
                return (try? data.write(to: snapshotURL, options: .atomic)) != nil
            },
            reload: { WidgetCenter.shared.reloadAllTimelines() }
        )
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated, error == nil else { return }
        sendPendingRequestIfPossible(using: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        sendPendingRequestIfPossible(using: session)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receivePayload(userInfo)
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        receivePayload(applicationContext)
    }

#if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
#endif
}
