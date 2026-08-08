import XCTest
@testable import ApexGaugeCore

final class SnapshotTests: XCTestCase {
    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = UsageSnapshot(providers: [
            ProviderSnapshot(provider: .claude, windows: [
                QuotaWindow(kind: .session, remainingPercent: 42),
                QuotaWindow(kind: .weekly, remainingPercent: 71),
                QuotaWindow(kind: .fable, remainingPercent: 18),
            ], fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)),
        ])

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
    }
}
