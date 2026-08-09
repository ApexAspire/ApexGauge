import Foundation
import Testing

@testable import ApexGaugeCore

/// 2026-08-06T07:06:40Z. Fixtures below are expressed relative to it.
private let fixedNow = Date(timeIntervalSince1970: 1_786_000_000)

private func makeFetcher(
    json: String?,
    containerFound: Bool = true,
    now: Date = fixedNow
) -> ClaudeBridgeFetcher {
    ClaudeBridgeFetcher(
        locateContainer: { containerFound ? URL(fileURLWithPath: "/tmp/apexgauge-tests") : nil },
        readData: { _ in
            guard let json else { throw CocoaError(.fileReadNoSuchFile) }
            return Data(json.utf8)
        },
        now: { now })
}

private func snapshotJSON(
    capturedAt: String = "2026-08-06T06:30:00Z",
    fiveHour: String? = #"{"usedPercent": 23.5, "resetsAt": "2026-08-06T11:00:00Z"}"#,
    sevenDay: String? = #"{"usedPercent": 81.0}"#,
    fable: String? = nil,
    version: Int = 1
) -> String {
    var fields = [
        "\"version\": \(version)",
        "\"capturedAt\": \"\(capturedAt)\"",
        "\"source\": \"claude-code-statusline\"",
    ]
    if let fiveHour { fields.append("\"fiveHour\": \(fiveHour)") }
    if let sevenDay { fields.append("\"sevenDay\": \(sevenDay)") }
    if let fable { fields.append("\"fable\": \(fable)") }
    return "{\(fields.joined(separator: ","))}"
}

/// The Fable row is driven purely by presence in the published file, so the app
/// needs no notion of which capture mode the Mac bridge is running in.
@Test func bridgeSurfacesFableOnlyWhenPublished() async throws {
    let without = try await makeFetcher(json: snapshotJSON()).fetchUsage()
    #expect(!without.windows.contains { $0.kind == .fable })

    let with = try await makeFetcher(
        json: snapshotJSON(fable: #"{"usedPercent": 18.0}"#)
    ).fetchUsage()
    let fable = try #require(with.windows.first { $0.kind == .fable })
    #expect(fable.remainingPercent == 82.0)
}

@Test func bridgeMapsUsedPercentToRemaining() async throws {
    let snapshot = try await makeFetcher(json: snapshotJSON()).fetchUsage()

    #expect(snapshot.provider == .claude)
    #expect(snapshot.windows.count == 2)

    let session = try #require(snapshot.windows.first { $0.kind == .session })
    #expect(session.remainingPercent == 76.5)
    #expect(session.resetsAt != nil)

    let weekly = try #require(snapshot.windows.first { $0.kind == .weekly })
    #expect(weekly.remainingPercent == 19.0)
    #expect(weekly.resetsAt == nil)
}

/// Each window is independently absent in the statusline payload, so a
/// five-hour-only capture must still produce a usable snapshot.
@Test func bridgeAcceptsPartialWindows() async throws {
    let snapshot = try await makeFetcher(json: snapshotJSON(sevenDay: nil)).fetchUsage()

    #expect(snapshot.windows.count == 1)
    #expect(snapshot.windows.first?.kind == .session)
}

/// fetchedAt must be read time, not capture time: the complication derives its
/// refresh cadence from it, and an idle capture time would pin it to a
/// permanent refresh loop.
@Test func bridgeStampsFetchedAtWithReadTime() async throws {
    let snapshot = try await makeFetcher(
        json: snapshotJSON(capturedAt: "2026-08-01T00:00:00Z")
    ).fetchUsage()

    #expect(snapshot.fetchedAt == fixedNow)
}

/// The pair that stops a refresh looking successful against an idle bridge:
/// read time drives the complication cadence, capture time drives what the user
/// is told.
@Test func bridgeReportsMeasurementTimeSeparatelyFromReadTime() async throws {
    let snapshot = try await makeFetcher(
        json: snapshotJSON(capturedAt: "2026-08-06T04:00:00Z")
    ).fetchUsage()

    #expect(snapshot.fetchedAt == fixedNow)
    #expect(snapshot.capturedAt == Date(timeIntervalSince1970: 1_785_988_800))
    #expect(snapshot.capturedAt != snapshot.fetchedAt)
    // Staleness is data now, not an error string masquerading as a failure.
    #expect(snapshot.lastError == nil)
}

/// A quiet bridge is not a failed one: stale data still renders, and the age is
/// carried as data so the UI can decide how to present it.
@Test func bridgeServesStaleCaptureAsDataNotError() async throws {
    // 5 days before fixedNow.
    let stale = try await makeFetcher(
        json: snapshotJSON(capturedAt: "2026-08-01T00:00:00Z")
    ).fetchUsage()

    #expect(stale.lastError == nil)
    #expect(stale.windows.count == 2)
    let age = try #require(stale.capturedAt.map { fixedNow.timeIntervalSince($0) })
    #expect(age > 5 * 60 * 60)
}

@Test func bridgeReportsNotConfiguredWithoutContainer() async {
    await #expect(throws: UsageFetchError.notConfigured) {
        try await makeFetcher(json: nil, containerFound: false).fetchUsage()
    }
}

@Test func bridgeReportsNotConfiguredWhenFileMissing() async {
    await #expect(throws: UsageFetchError.notConfigured) {
        try await makeFetcher(json: nil).fetchUsage()
    }
}

/// An empty capture is indistinguishable from "bridge installed but Claude Code
/// has not run yet", which is a setup state rather than usable data.
@Test func bridgeReportsNotConfiguredWhenNoWindowsPresent() async {
    await #expect(throws: UsageFetchError.notConfigured) {
        try await makeFetcher(json: snapshotJSON(fiveHour: nil, sevenDay: nil)).fetchUsage()
    }
}

@Test func bridgeRejectsNewerSnapshotVersion() async throws {
    await #expect(throws: UsageFetchError.self) {
        try await makeFetcher(json: snapshotJSON(version: 99)).fetchUsage()
    }
}

@Test func bridgeReportsDecodingFailureForGarbage() async throws {
    await #expect(throws: UsageFetchError.self) {
        try await makeFetcher(json: "{not json at all").fetchUsage()
    }
}
