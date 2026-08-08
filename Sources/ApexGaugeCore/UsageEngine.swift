import Foundation

public struct UsageEngine: UsageEngineing {
    private let claude: any UsageFetching
    private let codex: any UsageFetching
    private let kimi: any UsageFetching
    private let now: @Sendable () -> Date

    public init(
        claude: any UsageFetching,
        codex: any UsageFetching,
        kimi: any UsageFetching,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.claude = claude
        self.codex = codex
        self.kimi = kimi
        self.now = now
    }

    public func refreshAll() async -> UsageSnapshot {
        async let claude = self.fetch(self.claude)
        async let codex = self.fetch(self.codex)
        async let kimi = self.fetch(self.kimi)
        let providers = await (claude, codex, kimi)
        return UsageSnapshot(providers: [providers.0, providers.1, providers.2])
    }

    private func fetch(_ fetcher: any UsageFetching) async -> ProviderSnapshot {
        do {
            return try await fetcher.fetchUsage()
        } catch {
            return ProviderSnapshot(
                provider: fetcher.provider,
                windows: [],
                fetchedAt: self.now(),
                lastError: Self.errorMessage(error))
        }
    }

    private static func errorMessage(_ error: Error) -> String {
        guard let error = error as? UsageFetchError else {
            return error.localizedDescription
        }
        switch error {
        case .notConfigured:
            return "Not configured"
        case .unauthorized:
            return "Unauthorized"
        case let .rateLimited(retryAfter):
            return retryAfter.map { "Rate limited; retry after \($0) seconds" } ?? "Rate limited"
        case let .http(status, body):
            return "HTTP \(status): \(body)"
        case let .decoding(message):
            return "Could not decode provider response: \(message)"
        case let .network(message):
            return "Network error: \(message)"
        }
    }
}
