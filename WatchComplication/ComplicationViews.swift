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
#if os(watchOS)
                AccessoryWidgetGroup {
                    HStack(spacing: 4) {
                        Text("ApexGauge")
                            .fontWeight(.semibold)
                        Spacer(minLength: 2)
                        Text(entry.displayPercentUsed ? "used" : "left")
                            .foregroundStyle(.secondary)
                        if let oldestFetchedAt = entry.oldestFetchedAt {
                            Text("as of \(formattedTime(oldestFetchedAt))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 9))
                } content: {
                    ProviderQuotaView(
                        provider: .claude,
                        snapshot: snapshot.provider(.claude),
                        displayPercentUsed: entry.displayPercentUsed
                    )
                    ProviderQuotaView(
                        provider: .codex,
                        snapshot: snapshot.provider(.codex),
                        displayPercentUsed: entry.displayPercentUsed
                    )
                    ProviderQuotaView(
                        provider: .kimi,
                        snapshot: snapshot.provider(.kimi),
                        displayPercentUsed: entry.displayPercentUsed
                    )
                }
                .accessoryWidgetGroupStyle(.roundedSquare)
#else
                VStack(spacing: 2) {
                    HStack(spacing: 4) {
                        Text("ApexGauge")
                            .fontWeight(.semibold)
                        Spacer(minLength: 2)
                        Text(entry.displayPercentUsed ? "used" : "left")
                            .foregroundStyle(.secondary)
                        if let oldestFetchedAt = entry.oldestFetchedAt {
                            Text("as of \(formattedTime(oldestFetchedAt))")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.system(size: 9))

                    HStack(spacing: 4) {
                        ProviderQuotaView(
                            provider: .claude,
                            snapshot: snapshot.provider(.claude),
                            displayPercentUsed: entry.displayPercentUsed
                        )
                        ProviderQuotaView(
                            provider: .codex,
                            snapshot: snapshot.provider(.codex),
                            displayPercentUsed: entry.displayPercentUsed
                        )
                        ProviderQuotaView(
                            provider: .kimi,
                            snapshot: snapshot.provider(.kimi),
                            displayPercentUsed: entry.displayPercentUsed
                        )
                    }
                }
#endif
            } else {
                VStack(spacing: 2) {
                    Image(systemName: "iphone.and.arrow.forward")
                        .font(.title3)
                    Text("Open ApexGauge")
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

    private func formattedTime(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
    }
}

private struct ProviderQuotaView: View {
    let provider: ProviderSnapshot.Provider
    let snapshot: ProviderSnapshot?
    let displayPercentUsed: Bool

    private var lowestRemaining: Double {
        snapshot?.windows.map(\.remainingPercent).min() ?? 0
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(provider.displayName)
                .font(.system(size: 8, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(windowReadouts)
                .font(.system(size: 7, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.45)

            Gauge(value: displayedPercent(for: lowestRemaining), in: 0...100) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .labelsHidden()
        }
    }

    private var windowReadouts: String {
        guard let snapshot, !snapshot.windows.isEmpty else { return "—" }

        return snapshot.windows
            .sorted { $0.kind.sortOrder < $1.kind.sortOrder }
            .map {
                "\($0.kind.compactLabel) \(Int(displayedPercent(for: $0.remainingPercent).rounded()))%"
            }
            .joined(separator: " ")
    }

    private func displayedPercent(for remainingPercent: Double) -> Double {
        clamped(displayPercentUsed ? 100 - remainingPercent : remainingPercent)
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

private extension ProviderSnapshot.Provider {
    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .kimi: "Kimi"
        }
    }

    var initial: String {
        String(displayName.prefix(1))
    }
}

private extension QuotaWindow.Kind {
    var compactLabel: String {
        switch self {
        case .session: "S"
        case .weekly: "W"
        case .fable: "F"
        case .other: "•"
        }
    }

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
