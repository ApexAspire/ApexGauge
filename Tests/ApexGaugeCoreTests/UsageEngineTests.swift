import Foundation
import XCTest
@testable import ApexGaugeCore

final class UsageEngineTests: XCTestCase {
    func testRefreshAllIsolatesProviderFailures() async throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let claude = EngineStubFetcher(provider: .claude) {
            ProviderSnapshot(
                provider: .claude,
                windows: [QuotaWindow(kind: .session, remainingPercent: 50)],
                fetchedAt: now)
        }
        let codex = EngineStubFetcher(provider: .codex) {
            throw UsageFetchError.unauthorized
        }
        let kimi = EngineStubFetcher(provider: .kimi) {
            ProviderSnapshot(
                provider: .kimi,
                windows: [QuotaWindow(kind: .weekly, remainingPercent: 75)],
                fetchedAt: now)
        }
        let engine = UsageEngine(claude: claude, codex: codex, kimi: kimi, now: { now })

        let snapshot = await engine.refreshAll()

        XCTAssertEqual(snapshot.providers.map(\.provider), [.claude, .codex, .kimi])
        XCTAssertEqual(snapshot.providers[0].windows.first?.remainingPercent, 50)
        XCTAssertEqual(snapshot.providers[1].windows, [])
        XCTAssertEqual(snapshot.providers[1].lastError, "Unauthorized")
        XCTAssertEqual(snapshot.providers[2].windows.first?.remainingPercent, 75)
    }
}

private struct EngineStubFetcher: UsageFetching {
    let provider: ProviderSnapshot.Provider
    let operation: @Sendable () async throws -> ProviderSnapshot

    init(
        provider: ProviderSnapshot.Provider,
        operation: @escaping @Sendable () async throws -> ProviderSnapshot
    ) {
        self.provider = provider
        self.operation = operation
    }

    func fetchUsage() async throws -> ProviderSnapshot {
        try await self.operation()
    }
}
