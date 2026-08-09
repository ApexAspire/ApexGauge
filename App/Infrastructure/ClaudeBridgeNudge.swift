import ApexGaugeCore
import Foundation

/// Asks the Mac bridge to republish, then waits a bounded time for a newer
/// capture to arrive.
///
/// It cannot make Claude Code produce fresh numbers — those exist only when
/// Claude Code renders its status line — so this closes the narrower gap where
/// the Mac holds a newer capture than iCloud has delivered. When nothing newer
/// lands within the deadline the caller shows the true capture age instead of
/// waiting indefinitely.
enum ClaudeBridgeNudge {
    static let requestFilename = "refresh-request.json"
    static let waitTimeout: TimeInterval = 10
    private static let pollInterval: Duration = .milliseconds(500)

    /// Writes the request marker and polls until a capture newer than
    /// `laterThan` appears. Returns the new capture date, or nil on timeout.
    @discardableResult
    static func requestRefresh(laterThan previousCapture: Date?) async -> Date? {
        guard let documents = ClaudeBridgeFetcher.defaultContainerURL() else { return nil }

        await Task.detached(priority: .userInitiated) {
            writeRequest(in: documents)
        }.value

        let deadline = Date().addingTimeInterval(waitTimeout)
        while Date() < deadline {
            try? await Task.sleep(for: pollInterval)

            let captured = await Task.detached(priority: .userInitiated) {
                publishedCaptureDate(in: documents)
            }.value

            guard let captured else { continue }
            guard let previousCapture else { return captured }
            if captured > previousCapture { return captured }
        }

        return nil
    }

    private static func writeRequest(in documents: URL) {
        let payload: [String: String] = [
            "requestedAt": ISO8601DateFormatter().string(from: Date()),
            "source": "ApexGauge iOS refresh",
        ]

        guard let data = try? JSONSerialization.data(
            withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        else {
            return
        }

        let url = documents.appendingPathComponent(requestFilename, isDirectory: false)
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    private static func publishedCaptureDate(in documents: URL) -> Date? {
        let url = documents.appendingPathComponent(
            ClaudeBridgeFetcher.snapshotFilename, isDirectory: false)
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(ClaudeBridgeSnapshot.self, from: data)
        else {
            return nil
        }
        return snapshot.capturedAt
    }
}
