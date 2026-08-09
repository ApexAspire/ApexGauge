import ApexGaugeCore
import Foundation

/// Where Claude subscription quota comes from.
///
/// `bridge` is the default and the only path Anthropic's Claude Code terms
/// describe as intended: Claude Code hands the numbers to its own statusline on
/// the Mac, and the bridge relays them through iCloud. `oauth` calls Anthropic
/// directly with the user's subscription token — opt-in, see ClaudeSettingsView
/// for the disclosure shown before it can be enabled.
enum ClaudeSource: String, CaseIterable, Sendable {
    case bridge
    case oauth

    static let preferenceKey = "ClaudeUsageSource"
    static let `default` = ClaudeSource.bridge

    var title: String {
        switch self {
        case .bridge: "Mac bridge"
        case .oauth: "OAuth token"
        }
    }

    static func current(_ defaults: UserDefaults = .standard) -> ClaudeSource {
        defaults.string(forKey: preferenceKey).flatMap(ClaudeSource.init(rawValue:)) ?? .default
    }
}

/// Asks the system for the iCloud container so it gets provisioned, and so the
/// Mac side of the bridge has somewhere to publish to.
///
/// Deliberately not gated on mock mode: mock mode promises not to contact
/// *providers*, and this touches only the user's own iCloud. Without it the
/// container would appear only after a first live refresh, which makes bridge
/// setup depend on an unrelated setting.
enum ICloudContainerWarmUp {
    /// Resolving the container URL alone does not make it appear on the user's
    /// Mac: CloudDocs refuses to create an unknown container locally, so the
    /// directory only mirrors once this device has put real content in it.
    /// Writing a marker is what gives the Mac side somewhere to publish to.
    static func run() {
        Task.detached(priority: .utility) {
            guard let documents = ClaudeBridgeFetcher.defaultContainerURL() else { return }

            do {
                try FileManager.default.createDirectory(
                    at: documents, withIntermediateDirectories: true)

                let marker = documents.appendingPathComponent("device.json", isDirectory: false)
                let payload: [String: String] = [
                    "device": "iPhone",
                    "app": "Apex Gauge",
                    "updatedAt": ISO8601DateFormatter().string(from: Date()),
                ]
                let data = try JSONSerialization.data(
                    withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: marker, options: .atomic)
            } catch {
                // Setup state, not a failure worth surfacing: the Settings
                // bridge status line reports whether the container is reachable.
            }
        }
    }

    /// Whether the app can currently see its iCloud container. Blocking, so
    /// callers stay off the main thread.
    static func isContainerAvailable() -> Bool {
        ClaudeBridgeFetcher.defaultContainerURL() != nil
    }
}

/// Chooses the Claude fetcher per call rather than at construction, so changing
/// the source in Settings takes effect on the next refresh without rebuilding
/// the engine or relaunching the app.
struct ClaudeRoutingFetcher: UsageFetching {
    let provider: ProviderSnapshot.Provider = .claude

    private let bridge: any UsageFetching
    private let oauth: any UsageFetching
    private let source: @Sendable () -> ClaudeSource

    init(
        bridge: any UsageFetching,
        oauth: any UsageFetching,
        source: @escaping @Sendable () -> ClaudeSource = { ClaudeSource.current() }
    ) {
        self.bridge = bridge
        self.oauth = oauth
        self.source = source
    }

    func fetchUsage() async throws -> ProviderSnapshot {
        switch self.source() {
        case .bridge: try await self.bridge.fetchUsage()
        case .oauth: try await self.oauth.fetchUsage()
        }
    }
}
