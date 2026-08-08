import ApexGaugeCore
import SwiftUI

struct QuotaWindowRow: View {
    let window: QuotaWindow
    let displayPercentUsed: Bool
    let displayResetCountdown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(kindLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .leading)

                Text("\(Int(displayedPercent.rounded()))% \(modeLabel)")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if let resetsAt = window.resetsAt {
                    Group {
                        if displayResetCountdown {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Text(countdownLabel(until: resetsAt, now: context.date))
                            }
                        } else {
                            Text(absoluteResetLabel(for: resetsAt))
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            ProgressView(value: displayedPercent, total: 100)
                .tint(gaugeColor)
                .accessibilityLabel("\(kindAccessibilityLabel) quota \(modeLabel)")
                .accessibilityValue("\(Int(displayedPercent.rounded())) percent")
        }
    }

    private var displayedPercent: Double {
        displayPercentUsed ? 100 - clampedPercent : clampedPercent
    }

    private var modeLabel: String {
        displayPercentUsed ? "used" : "left"
    }

    private var clampedPercent: Double {
        min(max(window.remainingPercent, 0), 100)
    }

    private var kindLabel: String {
        switch window.kind {
        case .session: "Session"
        case .weekly: "Week"
        case .fable: "Fable"
        case .other: "Other"
        }
    }

    private func absoluteResetLabel(for date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.abbreviated))
        let time = date.formatted(date: .omitted, time: .shortened)
        return "Resets \(weekday) \(time)"
    }

    private func countdownLabel(until date: Date, now: Date) -> String {
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

    private var kindAccessibilityLabel: String {
        switch window.kind {
        case .session: "Session"
        case .weekly: "Weekly"
        case .fable: "Fable"
        case .other: "Other"
        }
    }

    private var gaugeColor: Color {
        switch clampedPercent {
        case ..<20: .red
        case ..<40: .orange
        default: .green
        }
    }
}
