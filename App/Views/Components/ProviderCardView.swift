import ApexGaugeCore
import SwiftUI

struct ProviderCardView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: ProviderSnapshot
    let displayPercentUsed: Bool
    let displayResetCountdown: Bool
    let isRefreshing: Bool
    let refreshDisabled: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ApexTheme.Spacing.standard) {
            header

            if snapshot.windows.isEmpty {
                Label("No quota data is available.", systemImage: "gauge.with.dots.needle.0percent")
                    .font(ApexTheme.Typography.compact)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, ApexTheme.Spacing.small)
            } else {
                VStack(spacing: ApexTheme.Spacing.small) {
                    ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                        QuotaWindowRow(
                            window: window,
                            displayPercentUsed: displayPercentUsed,
                            displayResetCountdown: displayResetCountdown
                        )
                    }
                }
            }

            if let error = snapshot.lastError {
                ErrorBannerView(message: error)
            }
        }
        .padding(ApexTheme.Spacing.standard)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: ApexTheme.Spacing.small) {
            if dynamicTypeSize.isAccessibilitySize {
                providerTitle

                HStack(spacing: ApexTheme.Spacing.medium) {
                    modeChip
                    Spacer(minLength: ApexTheme.Spacing.small)
                    refreshButton
                }
            } else {
                HStack(alignment: .center, spacing: ApexTheme.Spacing.medium) {
                    providerTitle
                    Spacer(minLength: ApexTheme.Spacing.small)
                    modeChip
                    refreshButton
                }
            }

            Label(
                "Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))",
                systemImage: "clock"
            )
            .font(ApexTheme.Typography.caption)
            .foregroundStyle(ApexTheme.Colors.inkSecondary)
        }
    }

    private var providerTitle: some View {
        Label(providerName, systemImage: providerSymbol)
            .font(ApexTheme.Typography.displaySmall)
            .foregroundStyle(ApexTheme.Colors.inkPrimary)
            .symbolRenderingMode(.monochrome)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var modeChip: some View {
        Text(displayPercentUsed ? "Used" : "Left")
            .font(ApexTheme.Typography.eyebrow)
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(ApexTheme.Colors.accent)
            .padding(.horizontal, ApexTheme.Spacing.small)
            .padding(.vertical, ApexTheme.Spacing.xSmall)
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

    private var providerSymbol: String {
        switch snapshot.provider {
        case .claude: "sparkles"
        case .codex: "terminal"
        case .kimi: "moon.stars"
        }
    }
}
