import ApexGaugeCore
import SwiftUI

struct ProviderCardView: View {
    let snapshot: ProviderSnapshot
    let displayPercentUsed: Bool
    let displayResetCountdown: Bool
    let isRefreshing: Bool
    let refreshDisabled: Bool
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(providerName, systemImage: providerSymbol)
                    .font(.headline)
                Spacer()
                Text(displayPercentUsed ? "used" : "left")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
                Text("as of \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onRefresh) {
                    if isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .frame(width: 24, height: 24)
                .disabled(refreshDisabled || isRefreshing)
                .accessibilityLabel("Refresh \(providerName)")
            }

            if snapshot.windows.isEmpty {
                Text("No quota windows available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    QuotaWindowRow(
                        window: window,
                        displayPercentUsed: displayPercentUsed,
                        displayResetCountdown: displayResetCountdown
                    )
                }
            }

            if let error = snapshot.lastError {
                ErrorBannerView(message: error)
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
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
