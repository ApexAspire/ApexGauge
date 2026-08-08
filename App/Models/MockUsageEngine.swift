import ApexGaugeCore
import Foundation

struct MockUsageEngine: UsageEngineing {
    func refreshAll() async -> UsageSnapshot {
        try? await Task.sleep(for: .milliseconds(500))

        let now = Date()
        return UsageSnapshot(providers: [
            ProviderSnapshot(
                provider: .claude,
                windows: [
                    QuotaWindow(kind: .session, remainingPercent: 42, resetsAt: now.addingTimeInterval(3 * 60 * 60)),
                    QuotaWindow(kind: .weekly, remainingPercent: 71, resetsAt: now.addingTimeInterval(4 * 24 * 60 * 60)),
                    QuotaWindow(kind: .fable, remainingPercent: 18, resetsAt: now.addingTimeInterval(2 * 24 * 60 * 60)),
                ],
                fetchedAt: now
            ),
            ProviderSnapshot(
                provider: .codex,
                windows: [
                    QuotaWindow(kind: .session, remainingPercent: 30, resetsAt: now.addingTimeInterval(2 * 60 * 60)),
                    QuotaWindow(kind: .weekly, remainingPercent: 55, resetsAt: now.addingTimeInterval(5 * 24 * 60 * 60)),
                ],
                fetchedAt: now
            ),
            ProviderSnapshot(
                provider: .kimi,
                windows: [
                    QuotaWindow(kind: .weekly, remainingPercent: 12, resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60)),
                ],
                fetchedAt: now
            ),
        ])
    }
}
