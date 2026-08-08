import Foundation
import XCTest
@testable import ApexGaugeCore

final class KimiUsageFetcherTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testHappyPathParsesStringFieldsAndMapsWeeklyThenFiveHourSession() async throws {
        let client = StubHTTPClient([.init(json: Self.usageJSON)])
        let store = MockCredentialStore(kimi: KimiCredentials(apiKey: "kimi-key"))
        let fetcher = KimiUsageFetcher(store: store, httpClient: client, now: { Self.now })

        let snapshot = try await fetcher.fetchUsage()

        XCTAssertEqual(snapshot.provider, .kimi)
        XCTAssertEqual(snapshot.windows.map(\.kind), [.weekly, .session])
        XCTAssertEqual(snapshot.windows[0].remainingPercent, 75, accuracy: 0.0001)
        XCTAssertEqual(snapshot.windows[1].remainingPercent, 80, accuracy: 0.0001)
        XCTAssertNotNil(snapshot.windows[0].resetsAt)
        XCTAssertNotNil(snapshot.windows[1].resetsAt)
        let requests = await client.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.kimi.com/coding/v1/usages")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer kimi-key")
    }

    func test401MapsToUnauthorized() async throws {
        let error = await self.fetchError(status: 401)
        XCTAssertEqual(error, .unauthorized)
    }

    func test429MapsRetryAfterSeconds() async throws {
        let error = await self.fetchError(status: 429, headers: ["Retry-After": "120"])
        XCTAssertEqual(error, .rateLimited(retryAfter: 120))
    }

    private func fetchError(status: Int, headers: [String: String] = [:]) async -> UsageFetchError? {
        let client = StubHTTPClient([.init(status: status, headers: headers, json: #"{"error":"test"}"#)])
        let store = MockCredentialStore(kimi: KimiCredentials(apiKey: "kimi-key"))
        let fetcher = KimiUsageFetcher(store: store, httpClient: client, now: { Self.now })
        do {
            _ = try await fetcher.fetchUsage()
            return nil
        } catch let error as UsageFetchError {
            return error
        } catch {
            return nil
        }
    }

    private static let usageJSON = #"""
    {
      "usage": {
        "limit": "2000",
        "used": "500",
        "remaining": "1500",
        "resetTime": "2027-01-09T15:23:13.373329235Z"
      },
      "limits": [
        {
          "window": {"duration": 300, "timeUnit": "TIME_UNIT_MINUTE"},
          "detail": {
            "limit": "200",
            "used": "40",
            "resetTime": "2027-01-06T15:05:24.374187075Z"
          }
        }
      ]
    }
    """#
}
