import ApexGaugeCore
import SwiftUI
import WidgetKit

struct ApexGaugeRectangularComplication: Widget {
    let kind = ApexGaugeDefaults.complicationKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationTimelineProvider()) { entry in
            RectangularComplicationView(entry: entry)
                .privacySensitive()
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Apex Gauge Usage")
        .description("Claude, Codex, and Kimi quota usage at a glance.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct ApexGaugeCircularComplication: Widget {
    let kind = "ApexGaugeComplicationCircular"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ComplicationTimelineProvider()) { entry in
            CircularComplicationView(entry: entry)
                .privacySensitive()
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Apex Gauge Lowest Quota")
        .description("The lowest remaining AI quota across all providers.")
        .supportedFamilies([.accessoryCircular])
    }
}

private struct RectangularComplicationView: View {
    let entry: ComplicationEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.providers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ProviderRowView(provider: .claude, snapshot: snapshot.provider(.claude), entry: entry)
                    ProviderRowView(provider: .codex, snapshot: snapshot.provider(.codex), entry: entry)
                    ProviderRowView(provider: .kimi, snapshot: snapshot.provider(.kimi), entry: entry)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.title3)
                    Text("Open Apex Gauge")
                        .font(.headline)
                    Text("on iPhone")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .opacity(entry.isStale ? 0.5 : 1)
    }
}

/// One provider row: brand-tinted symbol, % numeral, thin RAG bar, compact
/// reset countdown. One bar per provider — the user picks which window each
/// row shows (default: lowest remaining).
private struct ProviderRowView: View {
    let provider: ProviderSnapshot.Provider
    let snapshot: ProviderSnapshot?
    let entry: ComplicationEntry

    private var window: QuotaWindow? {
        snapshot?.window(for: entry.windowChoices[provider] ?? .lowest)
    }

    private var displayedPercent: Double {
        guard let window else { return 0 }
        return clamped(entry.displayPercentUsed ? 100 - window.remainingPercent : window.remainingPercent)
    }

    private var barColor: Color {
        switch window?.remainingPercent ?? 0 {
        case ..<25: .red
        case ..<50: .orange
        default: .green
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: provider.symbol)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(provider.brandTint)
                .frame(width: 12)

            Text(window == nil ? "—" : "\(Int(displayedPercent.rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 30, alignment: .trailing)

            ComplicationGaugeBar(value: displayedPercent, tint: barColor)
                .frame(maxWidth: .infinity)

            if let resetsAt = window?.resetsAt {
                Text(compactReset(until: resetsAt))
                    .font(.system(size: 8, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }

    /// Compact countdown with no spaces: "3h12m", "2d4h", "45m".
    private func compactReset(until date: Date) -> String {
        let interval = date.timeIntervalSince(entry.date)
        guard interval > 0 else { return "now" }

        let totalMinutes = max(1, Int(ceil(interval / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return hours > 0 ? "\(days)d\(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h\(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }
}

private struct ComplicationGaugeBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * clamped(value) / 100)
            }
        }
        .frame(height: 3.5)
    }
}

private struct CircularComplicationView: View {
    let entry: ComplicationEntry

    var body: some View {
        Group {
            if let worstQuota = entry.snapshot?.worstQuota {
                let displayedPercent = clamped(
                    entry.displayPercentUsed
                        ? 100 - worstQuota.remainingPercent
                        : worstQuota.remainingPercent
                )

                Gauge(value: displayedPercent, in: 0...100) {
                    Text(worstQuota.provider.initial)
                        .fontWeight(.bold)
                } currentValueLabel: {
                    Text("\(Int(displayedPercent.rounded()))")
                        .monospacedDigit()
                }
                .gaugeStyle(.accessoryCircularCapacity)
            } else {
                ZStack {
                    Circle()
                        .stroke(.secondary, lineWidth: 3)
                    Image(systemName: "iphone")
                }
            }
        }
        .opacity(entry.isStale ? 0.5 : 1)
    }
}

private struct WorstQuota {
    let provider: ProviderSnapshot.Provider
    let remainingPercent: Double
}

private extension UsageSnapshot {
    func provider(_ provider: ProviderSnapshot.Provider) -> ProviderSnapshot? {
        providers.first { $0.provider == provider }
    }

    var worstQuota: WorstQuota? {
        providers.compactMap { providerSnapshot in
            providerSnapshot.windows.min(by: { $0.remainingPercent < $1.remainingPercent }).map {
                WorstQuota(
                    provider: providerSnapshot.provider,
                    remainingPercent: $0.remainingPercent
                )
            }
        }
        .min { $0.remainingPercent < $1.remainingPercent }
    }
}

extension ProviderSnapshot.Provider {
    var initial: String {
        String(displayName.prefix(1))
    }

    var symbol: String {
        switch self {
        case .claude: "sparkles"
        case .codex: "terminal"
        case .kimi: "moon.stars"
        }
    }

    /// Brand-tinted symbol colour (bars carry the RAG meaning instead).
    var brandTint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34) // Anthropic coral
        case .codex: .white
        case .kimi: Color(red: 0.42, green: 0.58, blue: 1.0)
        }
    }
}

private extension QuotaWindow.Kind {
    var sortOrder: Int {
        switch self {
        case .session: 0
        case .weekly: 1
        case .fable: 2
        case .other: 3
        }
    }
}

private func clamped(_ percentage: Double) -> Double {
    min(max(percentage, 0), 100)
}
