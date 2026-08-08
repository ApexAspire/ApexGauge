import ApexGaugeCore
import Foundation

actor WatchSnapshotStore {
    func load() throws -> UsageSnapshot? {
        let snapshotURL = try snapshotURL()

        guard FileManager.default.fileExists(atPath: snapshotURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: snapshotURL)
        return try JSONDecoder().decode(UsageSnapshot.self, from: data)
    }

    func save(_ snapshot: UsageSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: try snapshotURL(), options: .atomic)
    }

    private func snapshotURL() throws -> URL {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ApexGaugeDefaults.appGroupID
        ) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [
                NSLocalizedDescriptionKey: "The ApexGauge App Group container is unavailable.",
            ])
        }

        return containerURL.appendingPathComponent(ApexGaugeDefaults.snapshotFilename)
    }
}
