import Foundation

// MARK: - Coordinator-owned: remote provider status
//
// A static JSON file hosted on GitHub Pages (docs/status.json in this repo)
// lets us flag a broken/changed provider endpoint to installed apps without
// shipping an update. The app polls it at most once per hour; a fetch failure
// is silent (no banner) — the file is advisory only.

public enum ProviderStatusLevel: String, Codable, Sendable {
    case ok, degraded, broken
}

public struct ProviderStatus: Codable, Sendable, Equatable {
    public var status: ProviderStatusLevel
    public var message: String

    public init(status: ProviderStatusLevel, message: String = "") {
        self.status = status
        self.message = message
    }
}

public struct ProviderStatusReport: Codable, Sendable, Equatable {
    public var version: Int
    public var updatedAt: String
    public var providers: [String: ProviderStatus]

    public init(version: Int, updatedAt: String, providers: [String: ProviderStatus]) {
        self.version = version
        self.updatedAt = updatedAt
        self.providers = providers
    }

    public func status(for provider: ProviderSnapshot.Provider) -> ProviderStatus? {
        providers[provider.rawValue]
    }
}

public enum ProviderStatusSource {
    /// Served by GitHub Pages from /docs on main.
    public static let url = URL(string: "https://apexaspire.github.io/ApexGauge/status.json")!

    /// UserDefaults key for the cached report JSON.
    public static let cacheKey = "ProviderStatusReportCache"

    /// UserDefaults key for the last successful fetch time.
    public static let lastFetchKey = "ProviderStatusLastFetch"

    /// Minimum interval between network fetches.
    public static let minimumFetchInterval: TimeInterval = 3600
}
