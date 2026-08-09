import ApexGaugeCore
import SwiftUI

struct ProviderCardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: ProviderSnapshot
    let displayPercentUsed: Bool
    let displayResetCountdown: Bool
    let providerStatus: ProviderStatus?
    let isRefreshing: Bool
    let refreshDisabled: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ApexTheme.Spacing.small) {
            header

            if let providerStatus, providerStatus.status != .ok {
                ProviderStatusBannerView(status: providerStatus)
            }

            if snapshot.windows.isEmpty {
                Label("No quota data is available.", systemImage: "gauge.with.dots.needle.0percent")
                    .font(ApexTheme.Typography.compact)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, ApexTheme.Spacing.small)
            } else {
                VStack(spacing: ApexTheme.Spacing.xSmall) {
                    ForEach(sortedWindows, id: \.offset) { _, window in
                        QuotaWindowRow(
                            window: window,
                            displayPercentUsed: displayPercentUsed,
                            displayResetCountdown: displayResetCountdown
                        )
                    }
                }
            }

            if let error = snapshot.lastError {
                ErrorBannerView(message: "Account connection issue — Apex Gauge could not refresh: \(error)")
            }
        }
        .padding(.horizontal, ApexTheme.Spacing.medium)
        .padding(.vertical, ApexTheme.Spacing.small)
        .apexSurface(cornerRadius: ApexTheme.Radius.card)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ApexTheme.Colors.accent)
                .frame(height: 2)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: ApexTheme.Radius.card,
                        topTrailingRadius: ApexTheme.Radius.card
                    )
                )
        }
    }

    /// Measurements older than one five-hour window mean the source has gone
    /// quiet, not that usage is flat — worth flagging rather than blending in.
    private static let staleMeasurementThreshold: TimeInterval = 5 * 60 * 60

    private var isMeasurementStale: Bool {
        (snapshot.measurementAge ?? 0) > Self.staleMeasurementThreshold
    }

    /// Reports when the numbers were *measured* wherever that differs from when
    /// they were read. Showing read time alone would make every pull-to-refresh
    /// look successful even against a bridge that has not updated in hours.
    private var freshnessLabel: String {
        guard let age = snapshot.measurementAge else {
            return "Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))"
        }

        let minutes = Int(age / 60)
        if minutes < 1 { return "Measured just now" }
        if minutes < 60 { return "Measured \(minutes)m ago" }

        let hours = Int(age / 3600)
        return hours < 24 ? "Measured \(hours)h ago" : "Measured \(hours / 24)d ago"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: ApexTheme.Spacing.small) {
            providerTitle

            if !dynamicTypeSize.isAccessibilitySize {
                Text(freshnessLabel)
                    .font(ApexTheme.Typography.dataCaption)
                    .foregroundStyle(
                        isMeasurementStale ? ApexTheme.Colors.warning : ApexTheme.Colors.inkSecondary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
            modeChip
            refreshButton
        }
        .frame(minHeight: 44)
    }

    private var providerTitle: some View {
        Label {
            Text(providerName)
        } icon: {
            Image(snapshot.provider.rawValue)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(snapshot.provider.brandTint)
                .frame(width: 20, height: 20)
        }
            .font(ApexTheme.Typography.displaySmall)
            .foregroundStyle(ApexTheme.Colors.inkPrimary)
            .lineLimit(1)
    }

    private var modeChip: some View {
        Text(displayPercentUsed ? "Used" : "Left")
            .font(ApexTheme.Typography.eyebrow)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(ApexTheme.Colors.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(ApexTheme.Colors.accentSoft, in: Capsule())
    }

    private var refreshButton: some View {
        Button(action: onRefresh) {
            Group {
                if isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(ApexTheme.Colors.accent)
        .disabled(refreshDisabled || isRefreshing)
        .accessibilityLabel("Refresh \(providerName)")
    }

    private var providerName: String {
        switch snapshot.provider {
        case .claude: "Claude"
        case .codex: "Codex"
        case .kimi: "Kimi"
        }
    }

    private var sortedWindows: [(offset: Int, element: QuotaWindow)] {
        snapshot.windows.enumerated().sorted { lhs, rhs in
            let lhsOrder = lhs.element.kind.sortOrder
            let rhsOrder = rhs.element.kind.sortOrder

            if lhsOrder == rhsOrder {
                return lhs.offset < rhs.offset
            }
            return lhsOrder < rhsOrder
        }
    }
}

private struct ProviderStatusBannerView: View {
    let status: ProviderStatus

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: ApexTheme.Spacing.xSmall) {
                Text(title)
                    .font(ApexTheme.Typography.caption.weight(.semibold))

                if !trimmedMessage.isEmpty {
                    Text(trimmedMessage)
                        .font(ApexTheme.Typography.caption)
                }
            }
        } icon: {
            Image(systemName: "network.slash")
        }
        .foregroundStyle(foregroundColor)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ApexTheme.Spacing.medium)
        .background(
            backgroundColor,
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
            .stroke(foregroundColor.opacity(0.35), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch status.status {
        case .ok:
            "Provider operating normally"
        case .degraded:
            "Provider issue — values may be stale"
        case .broken:
            "Provider endpoint unavailable"
        }
    }

    private var trimmedMessage: String {
        status.message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var foregroundColor: Color {
        status.status == .degraded ? ApexTheme.Colors.warning : ApexTheme.Colors.danger
    }

    private var backgroundColor: Color {
        status.status == .degraded ? ApexTheme.Colors.warningSoft : ApexTheme.Colors.dangerSoft
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
