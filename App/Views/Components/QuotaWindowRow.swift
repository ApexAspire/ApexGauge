import ApexGaugeCore
import SwiftUI

struct QuotaWindowRow: View {
    let window: QuotaWindow
    let displayPercentUsed: Bool
    let displayResetCountdown: Bool

    var body: some View {
        HStack(spacing: ApexTheme.Spacing.small) {
            Text(kindLabel)
                .font(ApexTheme.Typography.label)
                .foregroundStyle(ApexTheme.Colors.inkPrimary)
                .lineLimit(1)
                .frame(width: 52, alignment: .leading)

            Text("\(Int(displayedPercent.rounded()))%")
                .font(ApexTheme.Typography.metric)
                .foregroundStyle(gaugeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 38, alignment: .trailing)
                .accessibilityLabel("\(Int(displayedPercent.rounded())) percent \(modeLabel)")

            ProgressView(value: displayedPercent, total: 100)
                .tint(gaugeColor)
                .scaleEffect(x: 1, y: 1.15, anchor: .center)
                .frame(minWidth: 36, maxWidth: .infinity)
                .accessibilityLabel("\(kindAccessibilityLabel) quota \(modeLabel)")
                .accessibilityValue("\(Int(displayedPercent.rounded())) percent")

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
                .font(ApexTheme.Typography.dataCaption)
                .foregroundStyle(ApexTheme.Colors.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .allowsTightening(true)
                .frame(maxWidth: 82, alignment: .trailing)
                .layoutPriority(1)
                .accessibilityLabel(resetAccessibilityLabel(for: resetsAt))
            }
        }
        .padding(.horizontal, ApexTheme.Spacing.small)
        .padding(.vertical, ApexTheme.Spacing.xSmall)
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
        return "\(weekday) \(time)"
    }

    private func countdownLabel(until date: Date, now: Date) -> String {
        let interval = date.timeIntervalSince(now)
        guard interval > 0 else { return "Now" }

        let totalMinutes = max(1, Int(ceil(interval / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h" : "\(days)d"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(minutes)m"
    }

    private func resetAccessibilityLabel(for date: Date) -> String {
        if displayResetCountdown {
            return "Resets in \(countdownLabel(until: date, now: .now))"
        }
        return "Resets \(absoluteResetLabel(for: date))"
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
