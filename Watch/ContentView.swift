import ApexGaugeCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var snapshotRequester: SnapshotRequester

    var body: some View {
        Group {
            if let snapshot = snapshotRequester.snapshot, !snapshot.providers.isEmpty {
                List {
                    ForEach(snapshot.providers.indices, id: \.self) { index in
                        let provider = snapshot.providers[index]

                        Section(providerName(provider.provider)) {
                            ForEach(provider.windows.indices, id: \.self) { windowIndex in
                                let window = provider.windows[windowIndex]

                                HStack {
                                    Text(kindLabel(window.kind))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(
                                        "\(displayedPercent(for: window.remainingPercent))% "
                                            + (snapshotRequester.displayPercentUsed ? "used" : "left")
                                    )
                                        .font(.caption)
                                }
                            }
                        }
                    }

                    if let fetchedAt = snapshot.providers.map(\.fetchedAt).min() {
                        Text("as of \(fetchedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Waiting for iPhone…",
                    systemImage: "iphone.and.arrow.forward",
                    description: Text("Open ApexGauge on your iPhone to send usage data.")
                )
            }
        }
        .navigationTitle("ApexGauge")
    }

    private func providerName(_ provider: ProviderSnapshot.Provider) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        case .kimi: "Kimi"
        }
    }

    private func kindLabel(_ kind: QuotaWindow.Kind) -> String {
        switch kind {
        case .session: "S"
        case .weekly: "W"
        case .fable: "F"
        case .other: "O"
        }
    }

    private func displayedPercent(for remainingPercent: Double) -> Int {
        let displayed = snapshotRequester.displayPercentUsed
            ? 100 - remainingPercent
            : remainingPercent
        return Int(min(max(displayed, 0), 100).rounded())
    }
}
