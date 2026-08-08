import ApexGaugeCore
import Foundation

struct UnavailableUsageEngine: UsageEngineing {
    func refreshAll() async -> UsageSnapshot {
        let now = Date()
        return UsageSnapshot(providers: ProviderSnapshot.Provider.allCases.map { provider in
            ProviderSnapshot(
                provider: provider,
                windows: [],
                fetchedAt: now,
                lastError: "Live provider fetching will be connected during core integration. Turn on Use Mock Data to preview ApexGauge."
            )
        })
    }
}
