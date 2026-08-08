import Foundation
import XCTest
@testable import ApexGaugeCore

final class CodexUsageFetcherTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testHappyPathMapsPrimaryAndSecondaryWindows() async throws {
        let client = StubHTTPClient([.init(json: Self.usageJSON)])
        let store = MockCredentialStore(codex: CodexCredentials(
            accessToken: "codex-access",
            refreshToken: "codex-refresh",
            accountID: "account-123"))
        let fetcher = CodexUsageFetcher(store: store, httpClient: client, now: { Self.now })

        let snapshot = try await fetcher.fetchUsage()

        XCTAssertEqual(snapshot.provider, .codex)
        XCTAssertEqual(snapshot.windows.map(\.kind), [.session, .weekly])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [75, 40])
        XCTAssertEqual(snapshot.windows[0].resetsAt, Date(timeIntervalSince1970: 1_800_001_000))
        let requests = await client.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer codex-access")
        XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-123")
    }

    func test401MapsToUnauthorized() async throws {
        let error = await self.fetchError(status: 401)
        XCTAssertEqual(error, .unauthorized)
    }

    func test429MapsRetryAfterSeconds() async throws {
        let error = await self.fetchError(status: 429, headers: ["Retry-After": "45"])
        XCTAssertEqual(error, .rateLimited(retryAfter: 45))
    }

    func testExpiredJWTRefreshesPersistsRotatedTokensAndUsesNewAccessToken() async throws {
        let expiredJWT = try makeJWT(expiration: Self.now.addingTimeInterval(-1))
        let client = StubHTTPClient([
            .init(json: #"{"access_token":"codex-new","refresh_token":"codex-rotated"}"#),
            .init(json: Self.usageJSON),
        ])
        let store = MockCredentialStore(codex: CodexCredentials(
            accessToken: expiredJWT,
            refreshToken: "codex-refresh",
            accountID: "account-123"))
        let fetcher = CodexUsageFetcher(store: store, httpClient: client, now: { Self.now })

        _ = try await fetcher.fetchUsage()

        let saved = await store.savedCodex()
        XCTAssertEqual(saved, [CodexCredentials(
            accessToken: "codex-new",
            refreshToken: "codex-rotated",
            accountID: "account-123")])
        let requests = await client.recordedRequests()
        XCTAssertEqual(requests.map { $0.httpMethod }, ["POST", "GET"])
        XCTAssertEqual(requests[0].url?.absoluteString, "https://auth.openai.com/oauth/token")
        let bodyData = try XCTUnwrap(requests[0].httpBody)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: String])
        XCTAssertEqual(body["client_id"], "app_EMoamEEZ73f0CkXaXp7hrann")
        XCTAssertEqual(body["scope"], "openid profile email")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer codex-new")
    }

    private func fetchError(status: Int, headers: [String: String] = [:]) async -> UsageFetchError? {
        let client = StubHTTPClient([.init(status: status, headers: headers, json: #"{"error":"test"}"#)])
        let store = MockCredentialStore(codex: CodexCredentials(
            accessToken: "codex-access",
            refreshToken: "",
            accountID: nil))
        let fetcher = CodexUsageFetcher(store: store, httpClient: client, now: { Self.now })
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
      "plan_type": "plus",
      "rate_limit": {
        "primary_window": {
          "used_percent": 25,
          "reset_at": 1800001000,
          "limit_window_seconds": 18000
        },
        "secondary_window": {
          "used_percent": 60,
          "reset_at": 1800600000,
          "limit_window_seconds": 604800
        }
      },
      "credits": {"has_credits": true, "unlimited": false, "balance": "10.5"}
    }
    """#
}
