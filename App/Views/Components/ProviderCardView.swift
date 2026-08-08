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
        VStack(alignment: .leading, spacing: ApexTheme.Spacing.small) {
            header

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
                ErrorBannerView(message: error)
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

    private var header: some View {
        HStack(alignment: .center, spacing: ApexTheme.Spacing.small) {
            providerTitle

            if !dynamicTypeSize.isAccessibilitySize {
                Text("Updated \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(ApexTheme.Typography.dataCaption)
                    .foregroundStyle(ApexTheme.Colors.inkSecondary)
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
        Label(providerName, systemImage: providerSymbol)
            .font(ApexTheme.Typography.displaySmall)
            .foregroundStyle(ApexTheme.Colors.inkPrimary)
            .symbolRenderingMode(.monochrome)
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

    private var providerSymbol: String {
        switch snapshot.provider {
        case .claude: "sparkles"
        case .codex: "terminal"
        case .kimi: "moon.stars"
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
