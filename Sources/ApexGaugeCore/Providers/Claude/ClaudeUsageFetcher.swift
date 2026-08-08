import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct ClaudeUsageFetcher: UsageFetching {
    public let provider: ProviderSnapshot.Provider = .claude

    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let refreshURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

    private let store: any CredentialStore
    private let httpClient: any HTTPClient
    private let now: @Sendable () -> Date

    public init(
        store: any CredentialStore,
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.store = store
        self.httpClient = httpClient
        self.now = now
    }

    public func fetchUsage() async throws -> ProviderSnapshot {
        guard var credentials = try await self.store.loadClaude() else {
            throw UsageFetchError.notConfigured
        }

        let accessToken = credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = credentials.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let expiresSoon = credentials.expiresAt.map {
            $0 <= self.now().addingTimeInterval(ProviderSupport.refreshLeeway)
        } ?? true

        if (accessToken.isEmpty || expiresSoon), !refreshToken.isEmpty {
            credentials = try await self.refresh(credentials, refreshToken: refreshToken)
        } else if accessToken.isEmpty {
            throw UsageFetchError.unauthorized
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await ProviderSupport.checkedData(for: request, using: self.httpClient)
        let response = try ProviderSupport.decode(UsageResponse.self, from: data)
        return ProviderSnapshot(provider: .claude, windows: response.quotaWindows, fetchedAt: self.now())
    }

    private func refresh(
        _ credentials: ClaudeCredentials,
        refreshToken: String
    ) async throws -> ClaudeCredentials {
        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken),
            URLQueryItem(name: "client_id", value: Self.clientID),
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let data = try await ProviderSupport.checkedData(for: request, using: self.httpClient)
        let response = try ProviderSupport.decode(TokenRefreshResponse.self, from: data)
        let refreshed = ClaudeCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? credentials.refreshToken,
            expiresAt: self.now().addingTimeInterval(response.expiresIn))
        do {
            try await self.store.saveClaude(refreshed)
        } catch {
            throw UsageFetchError.network("Could not persist refreshed Claude credentials: \(error.localizedDescription)")
        }
        return refreshed
    }
}

private extension ClaudeUsageFetcher {
    struct TokenRefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresIn = "expires_in"
        }
    }

    struct UsageResponse: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        let sevenDaySonnet: Window?
        let sevenDayOpus: Window?
        let limits: [Limit]

        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
            case sevenDaySonnet = "seven_day_sonnet"
            case sevenDayOpus = "seven_day_opus"
            case limits
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.fiveHour = try container.decodeIfPresent(Window.self, forKey: .fiveHour)
            self.sevenDay = try container.decodeIfPresent(Window.self, forKey: .sevenDay)
            self.sevenDaySonnet = try container.decodeIfPresent(Window.self, forKey: .sevenDaySonnet)
            self.sevenDayOpus = try container.decodeIfPresent(Window.self, forKey: .sevenDayOpus)
            self.limits = (try? container.decodeIfPresent([Limit].self, forKey: .limits)) ?? []
        }

        var quotaWindows: [QuotaWindow] {
            var result: [QuotaWindow] = []
            if let fiveHour { result.append(fiveHour.quotaWindow(kind: .session)) }
            if let sevenDay { result.append(sevenDay.quotaWindow(kind: .weekly)) }
            if let sevenDaySonnet { result.append(sevenDaySonnet.quotaWindow(kind: .other)) }
            if let sevenDayOpus { result.append(sevenDayOpus.quotaWindow(kind: .other)) }
            result += self.limits.compactMap(\.fableQuotaWindow)
            return result
        }
    }

    struct Window: Decodable {
        let utilization: Double
        let resetsAt: String?

        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }

        func quotaWindow(kind: QuotaWindow.Kind) -> QuotaWindow {
            QuotaWindow(
                kind: kind,
                remainingPercent: ProviderSupport.remainingPercent(fromUsed: self.utilization),
                resetsAt: ProviderSupport.parseDate(self.resetsAt))
        }
    }

    struct Limit: Decodable {
        let percent: Double?
        let utilization: Double?
        let resetsAt: String?
        let scope: Scope?

        enum CodingKeys: String, CodingKey {
            case percent
            case utilization
            case resetsAt = "resets_at"
            case scope
        }

        var fableQuotaWindow: QuotaWindow? {
            guard let displayName = self.scope?.model?.displayName,
                  displayName.localizedCaseInsensitiveContains("fable"),
                  let usedPercent = self.percent ?? self.utilization
            else { return nil }
            return QuotaWindow(
                kind: .fable,
                remainingPercent: ProviderSupport.remainingPercent(fromUsed: usedPercent),
                resetsAt: ProviderSupport.parseDate(self.resetsAt))
        }
    }

    struct Scope: Decodable {
        let model: Model?
    }

    struct Model: Decodable {
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
        }
    }
}
