import ApexGaugeCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var snapshotRequester: SnapshotRequester

    var body: some View {
        Group {
            if let snapshot = snapshotRequester.snapshot, !snapshot.providers.isEmpty {
                List {
                    ForEach(snapshot.providers.indices, id: \.self) { index in
                        let provider = snapshot.providers[index]

                        Section {
                            if let state = provider.bridgeState {
                                // The phone is reachable; it is the Mac bridge that is
                                // quiet. Distinct from "Waiting for iPhone" below.
                                Label(state.watchText, systemImage: "desktopcomputer")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(sortedWindows(provider.windows).indices, id: \.self) { windowIndex in
                                WindowRow(
                                    window: sortedWindows(provider.windows)[windowIndex],
                                    displayPercentUsed: snapshotRequester.displayPercentUsed
                                )
                            }
                        } header: {
                            Label {
                                Text(providerName(provider.provider))
                            } icon: {
                                Image(provider.provider.rawValue)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(provider.provider.brandTint)
                                    .frame(width: 14, height: 14)
                            }
                        }
                    }

                    if let fetchedAt = snapshot.providers.map(\.fetchedAt).min() {
                        Text("as of \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Waiting for iPhone…",
                    systemImage: "iphone.and.arrow.forward",
                    description: Text("Open Apex Gauge on your iPhone to send usage data.")
                )
            }
        }
        .navigationTitle("Apex Gauge")
    }

    private func providerName(_ provider: ProviderSnapshot.Provider) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        case .kimi: "Kimi"
        }
    }

    private func sortedWindows(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        windows.enumerated().sorted { lhs, rhs in
            if lhs.element.kind.sortOrder == rhs.element.kind.sortOrder {
                return lhs.offset < rhs.offset
            }
            return lhs.element.kind.sortOrder < rhs.element.kind.sortOrder
        }.map(\.element)
    }
}

private struct WindowRow: View {
    let window: QuotaWindow
    let displayPercentUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(kindLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Spacer(minLength: 4)
                Text("\(displayedPercent)%")
                    .font(.callout.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundStyle(barColor)
            }

            ThinGaugeBar(value: displayedPercent, tint: barColor)

            if let resetsAt = window.resetsAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(resetLabel(until: resetsAt, now: context.date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var displayedPercent: Int {
        let displayed = displayPercentUsed ? 100 - window.remainingPercent : window.remainingPercent
        return Int(min(max(displayed, 0), 100).rounded())
    }

    private var kindLabel: String {
        switch window.kind {
        case .session: "Session"
        case .weekly: "Week"
        case .fable: "Fable"
        case .other: "Other"
        }
    }

    private var barColor: Color {
        switch window.remainingPercent {
        case ..<25: .red
        case ..<50: .orange
        default: .green
        }
    }

    private func resetLabel(until date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Resets now" }

        let totalMinutes = max(1, Int(ceil(interval / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "Resets in \(days)d \(hours)h" : "Resets in \(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "Resets in \(hours)h \(minutes)m" : "Resets in \(hours)h"
        }
        return "Resets in \(minutes)m"
    }
}

/// A slim 3pt gauge — ProgressView renders too chunky at watch scale.
private struct ThinGaugeBar: View {
    let value: Int
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: geometry.size.width * CGFloat(value) / 100)
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
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
