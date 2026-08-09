import ApexGaugeCore
import Foundation

actor SnapshotStore {
    func save(_ snapshot: UsageSnapshot) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ApexGaugeDefaults.appGroupID
        ) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The Apex Gauge App Group container is unavailable.",
            ])
        }

        let data = try JSONEncoder().encode(snapshot)
        let snapshotURL = containerURL.appendingPathComponent(ApexGaugeDefaults.snapshotFilename)
        try data.write(to: snapshotURL, options: .atomic)
    }

    /// Last snapshot written, for pushes that must not trigger a live refresh —
    /// notably the one sent the moment a watch app appears.
    func load() -> UsageSnapshot? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ApexGaugeDefaults.appGroupID
        ) else {
            return nil
        }

        let snapshotURL = containerURL.appendingPathComponent(ApexGaugeDefaults.snapshotFilename)
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
