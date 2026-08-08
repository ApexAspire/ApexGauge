import ApexGaugeCore
import SwiftUI

struct QuotaWindowRow: View {
    let window: QuotaWindow
    let displayPercentUsed: Bool
    let displayResetCountdown: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ApexTheme.Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: ApexTheme.Spacing.small) {
                Text(kindLabel)
                    .font(ApexTheme.Typography.eyebrow)
                    .foregroundStyle(ApexTheme.Colors.inkPrimary)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)

                if let resetsAt = window.resetsAt {
                    Spacer(minLength: ApexTheme.Spacing.small)

                    Group {
                        if displayResetCountdown {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                Text(countdownResetLabel(until: resetsAt, now: context.date))
                            }
                        } else {
                            Text(absoluteResetLabel(for: resetsAt))
                        }
                    }
                    .font(ApexTheme.Typography.dataCaption)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .accessibilityLabel(resetAccessibilityLabel(for: resetsAt))
                }
            }

            HStack(spacing: ApexTheme.Spacing.small) {
                ProgressView(value: displayedPercent, total: 100)
                    .tint(gaugeColor)
                    .scaleEffect(x: 1, y: 1.15, anchor: .center)
                    .frame(minWidth: 36, maxWidth: .infinity)
                    .accessibilityLabel("\(kindAccessibilityLabel) quota \(modeLabel)")
                    .accessibilityValue("\(Int(displayedPercent.rounded())) percent")

                Text("\(Int(displayedPercent.rounded()))%")
                    .font(ApexTheme.Typography.metric)
                    .foregroundStyle(gaugeColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: 42, alignment: .trailing)
                    .accessibilityLabel("\(Int(displayedPercent.rounded())) percent \(modeLabel)")
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
        return "Resets \(weekday) \(time)"
    }

    private func countdownResetLabel(until date: Date, now: Date) -> String {
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

    private func resetAccessibilityLabel(for date: Date) -> String {
        if displayResetCountdown {
            return countdownResetLabel(until: date, now: .now)
        }
        return absoluteResetLabel(for: date)
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
