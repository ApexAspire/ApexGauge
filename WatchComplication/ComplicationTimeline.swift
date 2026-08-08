import ApexGaugeCore
import Foundation
import WidgetKit

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let displayPercentUsed: Bool
    let windowChoices: [ProviderSnapshot.Provider: ComplicationWindowChoice]

    init(
        date: Date,
        snapshot: UsageSnapshot?,
        displayPercentUsed: Bool = true,
        windowChoices: [ProviderSnapshot.Provider: ComplicationWindowChoice] = [:]
    ) {
        self.date = date
        self.snapshot = snapshot
        self.displayPercentUsed = displayPercentUsed
        self.windowChoices = windowChoices
    }

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
        let entry = entry(at: Date())
        requestRefreshIfNeeded(for: entry.snapshot)
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date()
        let timeline = Timeline(
            entries: [entry(at: now)],
            policy: .after(now.addingTimeInterval(refreshInterval))
        )
        requestRefreshIfNeeded(for: timeline.entries.first?.snapshot)
        completion(timeline)
    }

    private func entry(at date: Date) -> ComplicationEntry {
        ComplicationEntry(
            date: date,
            snapshot: CachedSnapshotReader.load(),
            displayPercentUsed: DisplayPreferenceReader.load(),
            windowChoices: ComplicationWindowPreferences.decode(
                from: UserDefaults(suiteName: ApexGaugeDefaults.appGroupID)
            )
        )
    }

    private func requestRefreshIfNeeded(for snapshot: UsageSnapshot?) {
        guard SnapshotFreshness.needsRefresh(snapshot) else { return }

        // Do not extend timeline generation for session activation or a reply.
        Task {
            ComplicationSnapshotRequester.shared.requestSnapshot()
        }
    }
}

private enum SnapshotFreshness {
    static func needsRefresh(_ snapshot: UsageSnapshot?, now: Date = Date()) -> Bool {
        guard let oldestFetchedAt = snapshot?.providers.map(\.fetchedAt).min() else {
            return true
        }
        return now.timeIntervalSince(oldestFetchedAt) > ApexGaugeDefaults.staleAfter / 3
    }
}

private enum DisplayPreferenceReader {
    static func load() -> Bool {
        UserDefaults(suiteName: ApexGaugeDefaults.appGroupID)?.object(
            forKey: ApexGaugeDefaults.displayPercentUsedKey
        ) as? Bool ?? true
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
