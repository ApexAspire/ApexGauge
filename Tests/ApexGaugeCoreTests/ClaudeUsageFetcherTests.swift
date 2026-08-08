import Foundation
import XCTest
@testable import ApexGaugeCore

final class ClaudeUsageFetcherTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testHappyPathMapsSessionWeeklySonnetAndFableToRemainingPercent() async throws {
        let client = StubHTTPClient([.init(json: Self.usageJSON)])
        let store = MockCredentialStore(claude: ClaudeCredentials(
            accessToken: "claude-access",
            refreshToken: "claude-refresh",
            expiresAt: Self.now.addingTimeInterval(3600)))
        let fetcher = ClaudeUsageFetcher(store: store, httpClient: client, now: { Self.now })

        let snapshot = try await fetcher.fetchUsage()

        XCTAssertEqual(snapshot.provider, .claude)
        XCTAssertEqual(snapshot.fetchedAt, Self.now)
        XCTAssertEqual(snapshot.windows.map(\.kind), [.session, .weekly, .other, .fable])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [88, 66, 44, 22])
        XCTAssertEqual(snapshot.windows.compactMap(\.resetsAt).count, 4)

        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.absoluteString, "https://api.anthropic.com/api/oauth/usage")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer claude-access")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "anthropic-beta"), "oauth-2025-04-20")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "User-Agent"), "claude-code/2.1.0")
    }

    func test401MapsToUnauthorized() async throws {
        let error = await self.fetchError(status: 401)
        XCTAssertEqual(error, .unauthorized)
    }

    func test429MapsRetryAfterSeconds() async throws {
        let error = await self.fetchError(status: 429, headers: ["Retry-After": "90"])
        XCTAssertEqual(error, .rateLimited(retryAfter: 90))
    }

    func testExpiredTokenRefreshesPersistsRotatedTokensAndUsesNewAccessToken() async throws {
        let client = StubHTTPClient([
            .init(json: #"{"access_token":"claude-new","refresh_token":"claude-rotated","expires_in":3600}"#),
            .init(json: Self.usageJSON),
        ])
        let store = MockCredentialStore(claude: ClaudeCredentials(
            accessToken: "claude-old",
            refreshToken: "claude-refresh",
            expiresAt: Self.now.addingTimeInterval(-1)))
        let fetcher = ClaudeUsageFetcher(store: store, httpClient: client, now: { Self.now })

        _ = try await fetcher.fetchUsage()

        let saved = await store.savedClaude()
        XCTAssertEqual(saved, [ClaudeCredentials(
            accessToken: "claude-new",
            refreshToken: "claude-rotated",
            expiresAt: Self.now.addingTimeInterval(3600))])
        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.map { $0.httpMethod }, ["POST", "GET"])
        XCTAssertEqual(requests[0].url?.absoluteString, "https://platform.claude.com/v1/oauth/token")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let refreshBody = String(data: try XCTUnwrap(requests[0].httpBody), encoding: .utf8)
        XCTAssertTrue(try XCTUnwrap(refreshBody).contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer claude-new")
    }

    private func fetchError(status: Int, headers: [String: String] = [:]) async -> UsageFetchError? {
        let client = StubHTTPClient([.init(status: status, headers: headers, json: #"{"error":"test"}"#)])
        let store = MockCredentialStore(claude: ClaudeCredentials(
            accessToken: "claude-access",
            refreshToken: "",
            expiresAt: Self.now.addingTimeInterval(3600)))
        let fetcher = ClaudeUsageFetcher(store: store, httpClient: client, now: { Self.now })
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
      "five_hour": {"utilization": 12, "resets_at": "2027-01-15T10:00:00Z"},
      "seven_day": {"utilization": 34, "resets_at": "2027-01-20T10:00:00Z"},
      "seven_day_sonnet": {"utilization": 56, "resets_at": "2027-01-21T10:00:00Z"},
      "limits": [
        {
          "kind": "weekly_scoped",
          "percent": 78,
          "resets_at": "2027-01-22T10:00:00Z",
          "scope": {"model": {"id": "claude-fable", "display_name": "Claude FABLE 5"}}
        }
      ]
    }
    """#
}
