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
        hasPendingRequest = false
        if shouldSend {
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
        guard let data = payload[ApexGaugeDefaults.watchSnapshotPayloadKey] as? Data,
              (try? JSONDecoder().decode(UsageSnapshot.self, from: data)) != nil,
              let containerURL = FileManager.default.containerURL(
                  forSecurityApplicationGroupIdentifier: ApexGaugeDefaults.appGroupID
              )
        else {
            return
        }

        let snapshotURL = containerURL.appendingPathComponent(ApexGaugeDefaults.snapshotFilename)
        guard (try? data.write(to: snapshotURL, options: .atomic)) != nil else {
            return
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        guard activationState == .activated, error == nil else { return }
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
