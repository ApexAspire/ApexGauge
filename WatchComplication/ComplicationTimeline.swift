import ApexGaugeCore
import Foundation
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?

    var oldestFetchedAt: Date? {
        snapshot?.providers.map(\.fetchedAt).min()
    }

    var isStale: Bool {
        guard let oldestFetchedAt else { return false }
        return date.timeIntervalSince(oldestFetchedAt) > ApexGaugeDefaults.staleAfter
    }
}

struct ComplicationTimelineProvider: TimelineProvider {
    private let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date()
        let timeline = Timeline(
            entries: [entry(at: now)],
            policy: .after(now.addingTimeInterval(refreshInterval))
        )
        completion(timeline)
    }

    private func entry(at date: Date) -> ComplicationEntry {
        ComplicationEntry(date: date, snapshot: CachedSnapshotReader.load())
    }
}

private enum CachedSnapshotReader {
    static func load() -> UsageSnapshot? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ApexGaugeDefaults.appGroupID
        ) else {
            return nil
        }

        let snapshotURL = containerURL.appendingPathComponent(ApexGaugeDefaults.snapshotFilename)
        guard let data = try? Data(contentsOf: snapshotURL) else {
            return nil
        }

        return try? JSONDecoder().decode(UsageSnapshot.self, from: data)
    }
}
