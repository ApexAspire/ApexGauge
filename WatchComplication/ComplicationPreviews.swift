import ApexGaugeCore
import Foundation
import WidgetKit

private let previewDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

private let previewSnapshot = UsageSnapshot(providers: [
    ProviderSnapshot(
        provider: .claude,
        windows: [
            QuotaWindow(kind: .session, remainingPercent: 42),
            QuotaWindow(kind: .weekly, remainingPercent: 71),
            QuotaWindow(kind: .fable, remainingPercent: 18),
        ],
        fetchedAt: previewDate
    ),
    ProviderSnapshot(
        provider: .codex,
        windows: [
            QuotaWindow(kind: .session, remainingPercent: 30),
            QuotaWindow(kind: .weekly, remainingPercent: 55),
        ],
        fetchedAt: previewDate
    ),
    ProviderSnapshot(
        provider: .kimi,
        windows: [
            QuotaWindow(kind: .weekly, remainingPercent: 12),
        ],
        fetchedAt: previewDate
    ),
])

#Preview("Rectangular", as: .accessoryRectangular) {
    ApexGaugeRectangularComplication()
} timeline: {
    ComplicationEntry(date: previewDate, snapshot: previewSnapshot)
}

#Preview("Circular", as: .accessoryCircular) {
    ApexGaugeCircularComplication()
} timeline: {
    ComplicationEntry(date: previewDate, snapshot: previewSnapshot)
}
