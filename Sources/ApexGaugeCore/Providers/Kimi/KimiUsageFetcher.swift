import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct KimiUsageFetcher: UsageFetching {
    public let provider: ProviderSnapshot.Provider = .kimi

    private static let usageURL = URL(string: "https://api.kimi.com/coding/v1/usages")!

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
        guard let credentials = try await self.store.loadKimi() else {
            throw UsageFetchError.notConfigured
        }
        let apiKey = credentials.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw UsageFetchError.notConfigured
        }

        var request = URLRequest(url: Self.usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await ProviderSupport.checkedData(for: request, using: self.httpClient)
        let response = try ProviderSupport.decode(UsageResponse.self, from: data)
        var windows = [try response.usage.quotaWindow(kind: .weekly)]
        if let session = response.limits?.first(where: { $0.window.isFiveHours }) {
            windows.append(try session.detail.quotaWindow(kind: .session))
        }
        return ProviderSnapshot(provider: .kimi, windows: windows, fetchedAt: self.now())
    }
}

private extension KimiUsageFetcher {
    struct UsageResponse: Decodable {
        let usage: Detail
        let limits: [RateLimit]?
    }

    struct RateLimit: Decodable {
        let window: Window
        let detail: Detail
    }

    struct Window: Decodable {
        let duration: Double
        let timeUnit: String

        var isFiveHours: Bool {
            switch self.timeUnit.uppercased() {
            case "TIME_UNIT_MINUTE", "MINUTE", "MINUTES":
                return self.duration == 300
            case "TIME_UNIT_HOUR", "HOUR", "HOURS":
                return self.duration == 5
            case "TIME_UNIT_SECOND", "SECOND", "SECONDS":
                return self.duration == 18_000
            default:
                return false
            }
        }
    }

    struct Detail: Decodable {
        let limit: String
        let used: String?
        let remaining: String?
        let resetTime: String?

        enum CodingKeys: String, CodingKey {
            case limit
            case used
            case remaining
            case resetTime
            case resetAt
            case resetTimeSnake = "reset_time"
            case resetAtSnake = "reset_at"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let limit = Self.stringValue(in: container, forKey: .limit) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.limit,
                    .init(codingPath: container.codingPath, debugDescription: "Kimi usage limit is missing"))
            }
            self.limit = limit
            self.used = Self.stringValue(in: container, forKey: .used)
            self.remaining = Self.stringValue(in: container, forKey: .remaining)
            self.resetTime = Self.stringValue(in: container, forKey: .resetTime)
                ?? Self.stringValue(in: container, forKey: .resetAt)
                ?? Self.stringValue(in: container, forKey: .resetTimeSnake)
                ?? Self.stringValue(in: container, forKey: .resetAtSnake)
        }

        func quotaWindow(kind: QuotaWindow.Kind) throws -> QuotaWindow {
            guard let limitValue = Double(self.limit), limitValue > 0 else {
                throw UsageFetchError.decoding("Kimi returned an invalid quota limit: \(self.limit)")
            }

            let remainingPercent: Double
            if let remaining = self.remaining, let remainingValue = Double(remaining) {
                remainingPercent = remainingValue / limitValue * 100
            } else if let used = self.used, let usedValue = Double(used) {
                remainingPercent = 100 - usedValue / limitValue * 100
            } else {
                throw UsageFetchError.decoding("Kimi returned neither a valid remaining nor used quota value")
            }

            return QuotaWindow(
                kind: kind,
                remainingPercent: min(100, max(0, remainingPercent)),
                resetsAt: ProviderSupport.parseDate(self.resetTime))
        }

        private static func stringValue(
            in container: KeyedDecodingContainer<CodingKeys>,
            forKey key: CodingKeys
        ) -> String? {
            if let string = try? container.decode(String.self, forKey: key) {
                return string
            }
            if let integer = try? container.decode(Int64.self, forKey: key) {
                return String(integer)
            }
            if let double = try? container.decode(Double.self, forKey: key) {
                return String(double)
            }
            return nil
        }
    }
}
