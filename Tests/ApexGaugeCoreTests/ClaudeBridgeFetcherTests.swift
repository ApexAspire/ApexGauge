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

/// "No data" is modelled, not thrown: each cause is a distinct state that
/// travels as data so the dashboard and watch can say what to do.
@Test func bridgeReportsICloudUnavailableWithoutContainer() async throws {
    let fetcher = makeFetcher(json: nil, containerFound: false)
    #expect(try fetcher.read() == .unavailable(.iCloudUnavailable))

    let snapshot = try await fetcher.fetchUsage()
    #expect(snapshot.bridgeState == .iCloudUnavailable)
    #expect(snapshot.windows.isEmpty)
    #expect(snapshot.lastError == nil)
    #expect(snapshot.capturedAt == nil)
}

/// File missing covers "helper not installed", "Claude Code not run" and
/// "plan exposes no rate_limits" (the helper writes nothing then): the phone
/// cannot tell these apart, so they share one state.
@Test func bridgeReportsNoCaptureWhenFileMissing() async throws {
    let fetcher = makeFetcher(json: nil)
    #expect(try fetcher.read() == .unavailable(.noCapture))
    #expect(try await fetcher.fetchUsage().bridgeState == .noCapture)
}

@Test func bridgeReportsNoWindowsWhenSnapshotEmpty() async throws {
    let fetcher = makeFetcher(json: snapshotJSON(fiveHour: nil, sevenDay: nil))
    #expect(try fetcher.read() == .unavailable(.noWindows))
    #expect(try await fetcher.fetchUsage().bridgeState == .noWindows)
}

@Test func bridgeHealthyReadCarriesNoBridgeState() async throws {
    let snapshot = try await makeFetcher(json: snapshotJSON()).fetchUsage()
    #expect(snapshot.bridgeState == nil)
    if case .available = try makeFetcher(json: snapshotJSON()).read() {} else {
        Issue.record("expected an available reading")
    }
}

/// Staleness stays a capturedAt matter: an old capture is healthy data.
@Test func bridgeStaleCaptureIsNotAnUnavailableState() async throws {
    let snapshot = try await makeFetcher(
        json: snapshotJSON(capturedAt: "2026-08-01T00:00:00Z")
    ).fetchUsage()
    #expect(snapshot.bridgeState == nil)
    #expect(snapshot.capturedAt != nil)
}

@Test func bridgeStateCopyIsNonEmptyForEveryCase() {
    for state in ClaudeBridgeState.allCases {
        #expect(!state.title.isEmpty)
        #expect(!state.detail.isEmpty)
        #expect(!state.watchText.isEmpty)
    }
}

/// Wire compatibility: the new field is additive in both directions.
@Test func providerSnapshotBridgeStateRoundTripsAndDegrades() throws {
    let original = ProviderSnapshot(
        provider: .claude, windows: [], fetchedAt: fixedNow, bridgeState: .noCapture)
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(ProviderSnapshot.self, from: data) == original)

    // Old phone -> new watch: field absent.
    let old = #"{"provider":"claude","windows":[],"fetchedAt":0}"#
    let decodedOld = try JSONDecoder().decode(ProviderSnapshot.self, from: Data(old.utf8))
    #expect(decodedOld.bridgeState == nil)

    // Newer phone with an unknown state -> this watch: nil, not a failure.
    let future = #"{"provider":"claude","windows":[],"fetchedAt":0,"bridgeState":"somethingNew"}"#
    let decodedFuture = try JSONDecoder().decode(ProviderSnapshot.self, from: Data(future.utf8))
    #expect(decodedFuture.bridgeState == nil)

    // New phone -> old watch: an unknown key is ignored by synthesized Codable;
    // asserted here by decoding with only the legacy keys present in the struct.
    struct LegacyProvider: Codable {
        var provider: ProviderSnapshot.Provider
        var windows: [QuotaWindow]
        var fetchedAt: Date
        var lastError: String?
        var capturedAt: Date?
    }
    #expect(throws: Never.self) {
        _ = try JSONDecoder().decode(LegacyProvider.self, from: data)
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

// MARK: - Merge rule (transient blips must not wipe last-known numbers)

private func withWindows() -> ProviderSnapshot {
    ProviderSnapshot(
        provider: .claude,
        windows: [QuotaWindow(kind: .session, remainingPercent: 60)],
        fetchedAt: fixedNow.addingTimeInterval(-600),
        capturedAt: fixedNow.addingTimeInterval(-3600))
}

private func unavailable(_ state: ClaudeBridgeState) -> ProviderSnapshot {
    ProviderSnapshot(provider: .claude, windows: [], fetchedAt: fixedNow, bridgeState: state)
}

@Test func mergeKeepsPriorWindowsAndAttachesState() {
    let previous = withWindows()
    let merged = unavailable(.iCloudUnavailable).carryingForward(from: previous)
    #expect(merged.windows == previous.windows)
    #expect(merged.capturedAt == previous.capturedAt)
    #expect(merged.fetchedAt == previous.fetchedAt)
    #expect(merged.bridgeState == .iCloudUnavailable)
}

@Test func mergeWithoutPriorWindowsStaysEmptyWithState() {
    let fresh = unavailable(.noCapture)
    #expect(fresh.carryingForward(from: nil) == fresh)
    var emptyPrior = withWindows()
    emptyPrior.windows = []
    #expect(fresh.carryingForward(from: emptyPrior) == fresh)
}

@Test func mergeDoesNotCarryMockOrOAuthWindowsIntoBridgeState() {
    var previous = withWindows()
    previous.capturedAt = nil
    let state = unavailable(.noCapture)
    #expect(state.carryingForward(from: previous) == state)
}

@Test func mergeLaterHealthyReadClearsState() {
    var stale = withWindows()
    stale.bridgeState = .noCapture
    let healthy = ProviderSnapshot(
        provider: .claude,
        windows: [QuotaWindow(kind: .session, remainingPercent: 50)],
        fetchedAt: fixedNow, capturedAt: fixedNow)
    let merged = healthy.carryingForward(from: stale)
    #expect(merged == healthy)
    #expect(merged.bridgeState == nil)
}
