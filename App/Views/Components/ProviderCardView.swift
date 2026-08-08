import ApexGaugeCore
import SwiftUI

struct ProviderCardView: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(providerName, systemImage: providerSymbol)
                    .font(.headline)
                Spacer()
                Text("as of \(snapshot.fetchedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if snapshot.windows.isEmpty {
                Text("No quota windows available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    QuotaWindowRow(window: window)
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
