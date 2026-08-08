import Foundation
import XCTest
@testable import ApexGaugeCore

final class ProviderStatusFetcherTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testDecodesAndCachesSuccessfulReport() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let client = StubHTTPClient([.init(json: Self.degradedJSON)])
        let fetcher = ProviderStatusFetcher(
            httpClient: client,
            defaults: defaults,
            now: { Self.now }
        )

        let report = await fetcher.fetch()

        XCTAssertEqual(report?.version, 1)
        XCTAssertEqual(report?.status(for: .claude), ProviderStatus(
            status: .degraded,
            message: "Usage endpoint is returning delayed data."
        ))
        XCTAssertNotNil(defaults.data(forKey: ProviderStatusSource.cacheKey))
        XCTAssertEqual(
            defaults.object(forKey: ProviderStatusSource.lastFetchKey) as? Date,
            Self.now
        )

        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url, ProviderStatusSource.url)
        XCTAssertEqual(requests[0].timeoutInterval, 10)
        XCTAssertEqual(requests[0].cachePolicy, .reloadIgnoringLocalCacheData)
    }

    func testSecondFetchWithinMinimumIntervalUsesCacheWithoutNetwork() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let client = StubHTTPClient([.init(json: Self.degradedJSON)])
        let fetcher = ProviderStatusFetcher(
            httpClient: client,
            defaults: defaults,
            now: { Self.now }
        )

        let first = await fetcher.fetch()
        let second = await fetcher.fetch()

        XCTAssertEqual(second, first)
        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func testFailureFallsBackToCachedReport() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let cached = ProviderStatusReport(
            version: 7,
            updatedAt: "2026-08-07T00:00:00Z",
            providers: ["codex": ProviderStatus(status: .broken, message: "Endpoint changed.")]
        )
        defaults.set(try JSONEncoder().encode(cached), forKey: ProviderStatusSource.cacheKey)
        let client = StubHTTPClient([.init(status: 500, json: #"{"error":"unavailable"}"#)])
        let fetcher = ProviderStatusFetcher(
            httpClient: client,
            defaults: defaults,
            now: { Self.now }
        )

        let report = await fetcher.fetch()

        XCTAssertEqual(report, cached)
        XCTAssertNil(defaults.object(forKey: ProviderStatusSource.lastFetchKey))
    }

    func testFailureWithNoCacheReturnsNil() async {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let client = StubHTTPClient([.init(json: "not-json")])
        let fetcher = ProviderStatusFetcher(
            httpClient: client,
            defaults: defaults,
            now: { Self.now }
        )

        let report = await fetcher.fetch()

        XCTAssertNil(report)
        XCTAssertNil(defaults.object(forKey: ProviderStatusSource.lastFetchKey))
    }

    private func makeDefaults() -> UserDefaults {
        let suiteName = "ProviderStatusFetcherTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: ProviderStatusSource.cacheKey)
        defaults.removeObject(forKey: ProviderStatusSource.lastFetchKey)
    }

    private static let degradedJSON = #"""
    {
      "version": 1,
      "updatedAt": "2026-08-08T00:00:00Z",
      "providers": {
        "claude": {
          "status": "degraded",
          "message": "Usage endpoint is returning delayed data."
        }
      }
    }
    """#
}
