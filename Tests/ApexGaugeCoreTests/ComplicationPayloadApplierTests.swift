import XCTest
@testable import ApexGaugeCore

final class ComplicationPayloadApplierTests: XCTestCase {
    private func snapshotData() throws -> Data {
        try JSONEncoder().encode(UsageSnapshot(providers: [
            ProviderSnapshot(provider: .claude, windows: [
                QuotaWindow(kind: .session, remainingPercent: 42),
            ], fetchedAt: Date(timeIntervalSince1970: 1_800_000_000)),
        ]))
    }

    private func run(_ payload: [String: Any], snapshotWriteSucceeds: Bool = true) -> (reloads: Int, writes: Int) {
        var reloads = 0
        var writes = 0
        ComplicationPayloadApplier.apply(
            payload,
            setData: { _, _ in writes += 1 },
            setBool: { _, _ in writes += 1 },
            writeSnapshot: { _ in writes += 1; return snapshotWriteSucceeds },
            reload: { reloads += 1 }
        )
        return (reloads, writes)
    }

    func testFullPayloadRequestsExactlyOneReload() throws {
        let payload: [String: Any] = [
            ApexGaugeDefaults.complicationWindowsKey: Data([1]),
            ApexGaugeDefaults.complicationHiddenProvidersKey: Data([2]),
            ApexGaugeDefaults.watchDisplayModePayloadKey: true,
            ApexGaugeDefaults.watchSnapshotPayloadKey: try snapshotData(),
        ]
        let result = run(payload)
        XCTAssertEqual(result.reloads, 1)
        XCTAssertEqual(result.writes, 4)
    }

    func testEmptyPayloadRequestsNoReload() {
        XCTAssertEqual(run([:]).reloads, 0)
    }

    func testUnrelatedKeysRequestNoReload() {
        XCTAssertEqual(run(["other": Data([1])]).reloads, 0)
    }

    func testUndecodableSnapshotRequestsNoReload() {
        let result = run([ApexGaugeDefaults.watchSnapshotPayloadKey: Data([0xFF])])
        XCTAssertEqual(result.reloads, 0)
        XCTAssertEqual(result.writes, 0)
    }

    func testFailedSnapshotWriteRequestsNoReload() throws {
        let result = run(
            [ApexGaugeDefaults.watchSnapshotPayloadKey: try snapshotData()],
            snapshotWriteSucceeds: false
        )
        XCTAssertEqual(result.reloads, 0)
    }

    func testSingleSettingRequestsOneReload() {
        XCTAssertEqual(run([ApexGaugeDefaults.watchDisplayModePayloadKey: false]).reloads, 1)
    }
}
