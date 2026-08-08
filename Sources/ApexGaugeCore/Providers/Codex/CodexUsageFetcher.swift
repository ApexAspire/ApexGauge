import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct CodexUsageFetcher: UsageFetching {
    public let provider: ProviderSnapshot.Provider = .codex

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private static let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

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
        guard var credentials = try await self.store.loadCodex() else {
            throw UsageFetchError.notConfigured
        }

        let accessToken = credentials.accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshToken = credentials.refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        if (accessToken.isEmpty || ProviderSupport.accessTokenExpiresSoon(accessToken, now: self.now())),
           !refreshToken.isEmpty
        {
            credentials = try await self.refresh(credentials, refreshToken: refreshToken)
        } else if accessToken.isEmpty {
            throw UsageFetchError.unauthorized
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = credentials.accountID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountID.isEmpty
        {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let data = try await ProviderSupport.checkedData(for: request, using: self.httpClient)
        let response = try ProviderSupport.decode(UsageResponse.self, from: data)
        return ProviderSnapshot(provider: .codex, windows: response.quotaWindows, fetchedAt: self.now())
    }

    private func refresh(
        _ credentials: CodexCredentials,
        refreshToken: String
    ) async throws -> CodexCredentials {
        var request = URLRequest(url: Self.refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body = [
            "client_id": Self.clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "scope": "openid profile email",
        ]
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw UsageFetchError.decoding(error.localizedDescription)
        }

        let data = try await ProviderSupport.checkedData(for: request, using: self.httpClient)
        let response = try ProviderSupport.decode(TokenRefreshResponse.self, from: data)
        let refreshed = CodexCredentials(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken ?? credentials.refreshToken,
            accountID: credentials.accountID)
        do {
            try await self.store.saveCodex(refreshed)
        } catch {
            throw UsageFetchError.network("Could not persist refreshed Codex credentials: \(error.localizedDescription)")
        }
        return refreshed
    }
}

private extension CodexUsageFetcher {
    struct TokenRefreshResponse: Decodable {
        let accessToken: String
        let refreshToken: String?

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
        }
    }

    struct UsageResponse: Decodable {
        let rateLimit: RateLimit?

        enum CodingKeys: String, CodingKey {
            case rateLimit = "rate_limit"
        }

        var quotaWindows: [QuotaWindow] {
            var result: [QuotaWindow] = []
            let useLegacySlotKinds = self.rateLimit?.primaryWindow?.limitWindowSeconds == nil
                && self.rateLimit?.secondaryWindow?.limitWindowSeconds == nil
            if let primary = self.rateLimit?.primaryWindow {
                let kind: QuotaWindow.Kind = useLegacySlotKinds ? .session : primary.kind
                result.append(primary.quotaWindow(kind: kind))
            }
            if let secondary = self.rateLimit?.secondaryWindow {
                let kind: QuotaWindow.Kind = useLegacySlotKinds ? .weekly : secondary.kind
                result.append(secondary.quotaWindow(kind: kind))
            }
            return result
        }
    }

    struct RateLimit: Decodable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct Window: Decodable {
        let usedPercent: Double
        let resetAt: TimeInterval?
        let limitWindowSeconds: Int?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }

        var kind: QuotaWindow.Kind {
            guard let limitWindowSeconds else { return .other }
            if (18_000 - 600)...(18_000 + 600) ~= limitWindowSeconds {
                return .session
            }
            if (604_800 - 3_600)...(604_800 + 3_600) ~= limitWindowSeconds {
                return .weekly
            }
            return .other
        }

        func quotaWindow(kind: QuotaWindow.Kind) -> QuotaWindow {
            QuotaWindow(
                kind: kind,
                remainingPercent: ProviderSupport.remainingPercent(fromUsed: self.usedPercent),
                resetsAt: self.resetAt.map(Date.init(timeIntervalSince1970:)))
        }
    }
}
