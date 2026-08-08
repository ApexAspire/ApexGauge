import ApexGaugeCore
import SwiftUI

struct QuotaWindowRow: View {
    let window: QuotaWindow
    let displayPercentUsed: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(kindLabel)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 20, alignment: .leading)

                Text("\(Int(displayedPercent.rounded()))% \(modeLabel)")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                if let resetsAt = window.resetsAt {
                    Text("Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
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
        case .session: "S"
        case .weekly: "W"
        case .fable: "F"
        case .other: "•"
        }
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
