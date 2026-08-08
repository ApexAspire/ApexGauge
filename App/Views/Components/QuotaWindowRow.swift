import ApexGaugeCore
import SwiftUI

struct QuotaWindowRow: View {
    let window: QuotaWindow
    let displayPercentUsed: Bool
    let displayResetCountdown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ApexTheme.Spacing.small) {
            HStack(alignment: .firstTextBaseline, spacing: ApexTheme.Spacing.small) {
                Text(kindLabel)
                    .font(ApexTheme.Typography.label)
                    .foregroundStyle(ApexTheme.Colors.inkPrimary)

                Spacer(minLength: ApexTheme.Spacing.small)

                Text("\(Int(displayedPercent.rounded()))% \(modeLabel)")
                    .font(ApexTheme.Typography.metric)
                    .foregroundStyle(gaugeColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            ProgressView(value: displayedPercent, total: 100)
                .tint(gaugeColor)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)
                .accessibilityLabel("\(kindAccessibilityLabel) quota \(modeLabel)")
                .accessibilityValue("\(Int(displayedPercent.rounded())) percent")

            if let resetsAt = window.resetsAt {
                Label {
                    Group {
                        if displayResetCountdown {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Text(countdownLabel(until: resetsAt, now: context.date))
                            }
                        } else {
                            Text(absoluteResetLabel(for: resetsAt))
                        }
                    }
                } icon: {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .font(ApexTheme.Typography.caption)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)
            }
        }
        .padding(ApexTheme.Spacing.medium)
        .background(
            ApexTheme.Colors.surfaceRaised,
            in: RoundedRectangle(
                cornerRadius: ApexTheme.Radius.innerCard,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: ApexTheme.Radius.innerCard,
                style: .continuous
            )
            .stroke(ApexTheme.Colors.border.opacity(0.8), lineWidth: 1)
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
        case ..<25: ApexTheme.Colors.danger
        case ..<50: ApexTheme.Colors.warning
        default: ApexTheme.Colors.success
        }
    }
}
