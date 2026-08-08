import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Loads the advisory provider-status report without allowing status-service
/// failures to interfere with usage refreshes.
public final class ProviderStatusFetcher: @unchecked Sendable {
    private let httpClient: any HTTPClient
    private let defaults: UserDefaults
    private let now: @Sendable () -> Date

    public init(
        httpClient: any HTTPClient = URLSessionHTTPClient(),
        defaults: UserDefaults = .standard,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.defaults = defaults
        self.now = now
    }

    public func fetch() async -> ProviderStatusReport? {
        let currentDate = now()
        if let lastFetch = defaults.object(forKey: ProviderStatusSource.lastFetchKey) as? Date,
           currentDate.timeIntervalSince(lastFetch) < ProviderStatusSource.minimumFetchInterval
        {
            return cachedReport()
        }

        var request = URLRequest(
            url: ProviderStatusSource.url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 10
        )
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let data = try await ProviderSupport.checkedData(for: request, using: httpClient)
            let report = try JSONDecoder().decode(ProviderStatusReport.self, from: data)
            let cachedData = try JSONEncoder().encode(report)
            defaults.set(cachedData, forKey: ProviderStatusSource.cacheKey)
            defaults.set(currentDate, forKey: ProviderStatusSource.lastFetchKey)
            return report
        } catch {
            return cachedReport()
        }
    }

    private func cachedReport() -> ProviderStatusReport? {
        guard let data = defaults.data(forKey: ProviderStatusSource.cacheKey) else {
            return nil
        }
        return try? JSONDecoder().decode(ProviderStatusReport.self, from: data)
    }
}
