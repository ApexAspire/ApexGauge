import ApexGaugeCore
import Foundation

actor SnapshotStore {
    func save(_ snapshot: UsageSnapshot) throws {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ApexGaugeDefaults.appGroupID
        ) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The ApexGauge App Group container is unavailable.",
            ])
        }

        let data = try JSONEncoder().encode(snapshot)
        let snapshotURL = containerURL.appendingPathComponent(ApexGaugeDefaults.snapshotFilename)
        try data.write(to: snapshotURL, options: .atomic)
    }
}
