import ApexGaugeCore
import Foundation

final class SnapshotChangeDetector {
    private static let filename = "last-pushed-snapshot.json"
    private static let minimumPercentageChange = 1.0
    private static let maximumPushAge: TimeInterval = 30 * 60

    private let fileURL: URL?
    private var lastPushedSnapshot: UsageSnapshot?
    private var lastPushDate: Date?

    init(fileManager: FileManager = .default) {
        fileURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: ApexGaugeDefaults.appGroupID
        )?.appendingPathComponent(Self.filename)

        guard let fileURL else { return }

        if let data = try? Data(contentsOf: fileURL) {
            lastPushedSnapshot = try? JSONDecoder().decode(UsageSnapshot.self, from: data)
        }

        lastPushDate = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
    }

    /// Pure decision: is this snapshot worth a (budgeted) watch push?
    /// Records nothing — call recordPush only after a confirmed send, so a
    /// swallowed transfer doesn't suppress retries.
    func shouldPush(_ snapshot: UsageSnapshot, now: Date = Date()) -> Bool {
        let pushAgeExceeded = lastPushDate.map {
            now.timeIntervalSince($0) > Self.maximumPushAge
        } ?? true

        return pushAgeExceeded || hasMeaningfulChange(from: lastPushedSnapshot, to: snapshot)
    }

    /// Call only after the snapshot was actually transferred to the watch.
    func recordPush(_ snapshot: UsageSnapshot, now: Date = Date()) throws {
        guard let fileURL else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The Apex Gauge App Group container is unavailable.",
            ])
        }

        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
        lastPushedSnapshot = snapshot
        lastPushDate = now
    }

    private func hasMeaningfulChange(
        from previous: UsageSnapshot?,
        to current: UsageSnapshot
    ) -> Bool {
        guard let previous else { return true }

        // The watch app renders bridge health directly. A state transition
        // must reach it even when the last-known quota percentages are kept.
        for provider in current.providers {
            let oldState = previous.providers.first { $0.provider == provider.provider }?.bridgeState
            if oldState != provider.bridgeState { return true }
        }

        let previousWindows = windowsByProviderAndKind(in: previous)
        let currentWindows = windowsByProviderAndKind(in: current)

        guard previousWindows.keys == currentWindows.keys else { return true }

        for key in previousWindows.keys {
            guard let oldValues = previousWindows[key],
                  let newValues = currentWindows[key],
                  oldValues.count == newValues.count
            else {
                return true
            }

            for (oldValue, newValue) in zip(oldValues, newValues) {
                if abs(oldValue - newValue) >= Self.minimumPercentageChange {
                    return true
                }
            }
        }

        return false
    }

    private func windowsByProviderAndKind(in snapshot: UsageSnapshot) -> [String: [Double]] {
        var result: [String: [Double]] = [:]

        for provider in snapshot.providers {
            for window in provider.windows {
                let key = "\(provider.provider.rawValue):\(window.kind.rawValue)"
                result[key, default: []].append(window.remainingPercent)
            }
        }

        return result.mapValues { $0.sorted() }
    }
}
