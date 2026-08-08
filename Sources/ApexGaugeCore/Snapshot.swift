import Foundation

/// A single quota window (e.g. Claude 5-hour session, Kimi weekly).
/// Values are 0...100 **remaining** percentages as shown on the complication.
public struct QuotaWindow: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case session   // 5-hour window ("S")
        case weekly    // 7-day window ("W")
        case fable     // Claude Fable model-scoped weekly window ("F")
        case other     // provider-specific extras (credits, routines, …)
    }

    public var kind: Kind
    public var remainingPercent: Double
    public var resetsAt: Date?

    public init(kind: Kind, remainingPercent: Double, resetsAt: Date? = nil) {
        self.kind = kind
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

/// One provider row on the complication.
public struct ProviderSnapshot: Codable, Sendable, Equatable {
    public enum Provider: String, Codable, Sendable, CaseIterable {
        case claude, codex, kimi
    }

    public var provider: Provider
    public var windows: [QuotaWindow]
    /// When the provider last answered successfully — drives the "as of HH:MM"
    /// stale indicator on the watch face.
    public var fetchedAt: Date
    /// Non-nil when the last refresh failed; the complication keeps showing the
    /// previous values (dimmed) and the iOS app surfaces this message.
    public var lastError: String?

    public init(provider: Provider, windows: [QuotaWindow], fetchedAt: Date, lastError: String? = nil) {
        self.provider = provider
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.lastError = lastError
    }
}

/// The payload persisted to the App Group by the iPhone app and transferred to
/// the watch via WatchConnectivity. Codable + versioned so the complication can
/// evolve without breaking installed watches.
public struct UsageSnapshot: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public var version: Int
    public var providers: [ProviderSnapshot]

    public init(version: Int = Self.currentVersion, providers: [ProviderSnapshot]) {
        self.version = version
        self.providers = providers
    }
}

/// Shared constants (coordinator-owned). The App Group ties the iOS app, watch
/// app, and complication extension together; all targets must use these values.
/// NOTE: bundle IDs live in the com.apexaspire.* namespace — the original
/// com.apex.apexgauge.* IDs collided with another team's App ID registration.
public enum ApexGaugeDefaults {
    public static let appGroupID = "group.com.apexaspire.apexgauge"
    public static let snapshotFilename = "usage-snapshot.json"
    public static let appBundleID = "com.apexaspire.apexgauge"
    public static let watchBundleID = "com.apexaspire.apexgauge.watch"

    /// WatchConnectivity payload key carrying the UsageSnapshot JSON `Data`.
    public static let watchSnapshotPayloadKey = "snapshot"

    /// BGAppRefreshTask identifier (must match BGTaskSchedulerPermittedIdentifiers).
    public static let backgroundRefreshTaskIdentifier = "com.apexaspire.apexgauge.refresh"

    /// Minimum spacing between background refreshes (watchOS/iOS budgets).
    public static let backgroundRefreshInterval: TimeInterval = 15 * 60

    /// WidgetKit complication identifiers (Phase 3).
    public static let complicationKind = "ApexGaugeComplication"
    public static let complicationBundleID = "com.apexaspire.apexgauge.watch.widgets"

    /// Snapshots older than this render dimmed with an "as of" timestamp.
    public static let staleAfter: TimeInterval = 45 * 60

    /// Display preference: "% used" (true, default) vs "% left" (false).
    /// Written by the iOS app (UserDefaults.standard + pushed to the watch);
    /// the watch app + complication read it from their App Group suite.
    public static let displayPercentUsedKey = "DisplayPercentUsed"

    /// WatchConnectivity payload key carrying the display preference (Bool).
    public static let watchDisplayModePayloadKey = "displayPercentUsed"
}
