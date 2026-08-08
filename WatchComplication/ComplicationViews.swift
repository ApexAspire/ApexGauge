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

    private var visibleProviders: [ProviderSnapshot.Provider] {
        ProviderSnapshot.Provider.allCases.filter { !entry.hiddenProviders.contains($0) }
    }

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, !snapshot.providers.isEmpty {
                if visibleProviders.isEmpty {
                    Text("All providers hidden")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(visibleProviders, id: \.self) { provider in
                            ProviderRowView(provider: provider, snapshot: snapshot.provider(provider), entry: entry)
                                .frame(maxHeight: .infinity)
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
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

/// One provider row: brand-tinted symbol, then two half-width mini-bars —
/// Session on the left, the user's chosen window (default Week) on the right.
/// Providers without a session window get a single full-width bar.
private struct ProviderRowView: View {
    let provider: ProviderSnapshot.Provider
    let snapshot: ProviderSnapshot?
    let entry: ComplicationEntry

    private var choice: ComplicationWindowChoice {
        entry.windowChoices[provider] ?? .weekly
    }

    private var sessionWindow: QuotaWindow? {
        snapshot?.windows.first { $0.kind == .session }
    }

    /// The second bar's window: the chosen kind, falling back to the lowest
    /// non-session window (so the two bars never duplicate).
    private var secondaryWindow: QuotaWindow? {
        guard let snapshot else { return nil }
        if choice != .lowest {
            let kind: QuotaWindow.Kind? = switch choice {
            case .session: .session
            case .weekly: .weekly
            case .fable: .fable
            case .lowest: nil
            }
            if let kind, let match = snapshot.windows.first(where: { $0.kind == kind }) {
                return match
            }
        }
        let nonSession = snapshot.windows.filter { $0.kind != .session }
        return (nonSession.isEmpty ? snapshot.windows : nonSession)
            .min(by: { $0.remainingPercent < $1.remainingPercent })
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(provider.rawValue)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(provider.brandTint)
                .frame(width: 15, height: 15)

            if let sessionWindow {
                MiniGauge(window: sessionWindow, entry: entry)
            }
            if let secondaryWindow {
                MiniGauge(window: secondaryWindow, entry: entry)
            }
            if sessionWindow == nil, secondaryWindow == nil {
                Text("—")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// A half-row gauge: % and reset flank a thin RAG bar.
private struct MiniGauge: View {
    let window: QuotaWindow
    let entry: ComplicationEntry

    private var displayedPercent: Double {
        clamped(entry.displayPercentUsed ? 100 - window.remainingPercent : window.remainingPercent)
    }

    private var barColor: Color {
        switch window.remainingPercent {
        case ..<25: .red
        case ..<50: .orange
        default: .green
        }
    }

    var body: some View {
        HStack(spacing: 2) {
            Text("\(Int(displayedPercent.rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)

            ComplicationGaugeBar(value: displayedPercent, tint: barColor)
                .frame(maxWidth: .infinity)

            if let resetsAt = window.resetsAt {
                Text(compactReset(until: resetsAt))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .frame(maxWidth: .infinity)
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
