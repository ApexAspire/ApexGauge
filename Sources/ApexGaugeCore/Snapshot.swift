import Foundation
import SwiftUI

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

        public var displayName: String {
            switch self {
            case .claude: "Claude"
            case .codex: "Codex"
            case .kimi: "Kimi"
            }
        }

        /// Brand tint for the provider icon (the vendored CodexBar icons are
        /// monochrome currentColor/white SVGs designed to be tinted).
        public var brandTint: Color {
            switch self {
            case .claude: Color(red: 0.85, green: 0.47, blue: 0.34) // Anthropic coral
            case .codex: .primary // OpenAI mark is monochrome; adapts light/dark
            case .kimi: Color(red: 0.42, green: 0.58, blue: 1.0)
            }
        }
    }

    public var provider: Provider
    public var windows: [QuotaWindow]
    /// When the provider last answered successfully — drives the "as of HH:MM"
    /// stale indicator on the watch face.
    public var fetchedAt: Date
    /// Non-nil when the last refresh failed; the complication keeps showing the
    /// previous values (dimmed) and the iOS app surfaces this message.
    public var lastError: String?
    /// When the numbers themselves were measured, where that differs from when
    /// this app read them — currently only the Claude Mac bridge, whose figures
    /// are as old as the last Claude Code status line render.
    ///
    /// `fetchedAt` deliberately tracks read time so the complication's
    /// staleness check keeps driving a sane refresh cadence. Without this
    /// second date, a refresh against an idle bridge would report "just now"
    /// for hours-old data. Optional so older cached snapshots still decode.
    public var capturedAt: Date?

    public init(
        provider: Provider,
        windows: [QuotaWindow],
        fetchedAt: Date,
        lastError: String? = nil,
        capturedAt: Date? = nil
    ) {
        self.provider = provider
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.lastError = lastError
        self.capturedAt = capturedAt
    }

    /// How old the underlying measurement is, for surfaces that must not imply
    /// a read is a measurement.
    public var measurementAge: TimeInterval? {
        capturedAt.map { Date().timeIntervalSince($0) }
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

    /// WatchConnectivity message key: the watch sends ["requestSnapshot": true]
    /// when its cached snapshot is stale; the phone refreshes and replies.
    public static let watchSnapshotRequestKey = "requestSnapshot"

    /// WatchConnectivity payload key + UserDefaults key carrying the per-provider
    /// complication window preferences (JSON of [String: String], provider
    /// rawValue → ComplicationWindowChoice rawValue).
    public static let complicationWindowsKey = "ComplicationWindows"

    /// WatchConnectivity payload key + UserDefaults key carrying the set of
    /// providers hidden from the complication (JSON of [String]).
    public static let complicationHiddenProvidersKey = "ComplicationHiddenProviders"
}

/// Which quota window a provider's complication row shows. `.lowest` (default)
/// picks the window with the least remaining quota.
public enum ComplicationWindowChoice: String, Codable, Sendable, CaseIterable {
    case lowest, session, weekly, fable

    public var displayName: String {
        switch self {
        case .lowest: "Lowest"
        case .session: "Session"
        case .weekly: "Week"
        case .fable: "Fable"
        }
    }
}

public extension ProviderSnapshot {
    /// The window a complication row should render for a user's choice.
    /// Falls back to the lowest-remaining window when the chosen kind is absent.
    func window(for choice: ComplicationWindowChoice) -> QuotaWindow? {
        let kind: QuotaWindow.Kind? = switch choice {
        case .lowest: nil
        case .session: .session
        case .weekly: .weekly
        case .fable: .fable
        }
        if let kind, let match = windows.first(where: { $0.kind == kind }) {
            return match
        }
        return windows.min(by: { $0.remainingPercent < $1.remainingPercent })
    }
}

/// Per-provider complication window preferences, persisted as
/// [provider rawValue: choice rawValue] JSON in UserDefaults.
public enum ComplicationWindowPreferences {
    public static func decode(from defaults: UserDefaults?) -> [ProviderSnapshot.Provider: ComplicationWindowChoice] {
        guard let data = defaults?.data(forKey: ApexGaugeDefaults.complicationWindowsKey),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return raw.reduce(into: [:]) { result, pair in
            if let provider = ProviderSnapshot.Provider(rawValue: pair.key),
               let choice = ComplicationWindowChoice(rawValue: pair.value)
            {
                result[provider] = choice
            }
        }
    }

    public static func encode(_ prefs: [ProviderSnapshot.Provider: ComplicationWindowChoice]) -> Data? {
        let raw = prefs.reduce(into: [String: String]()) { $0[$1.key.rawValue] = $1.value.rawValue }
        return try? JSONEncoder().encode(raw)
    }

    public static func store(_ prefs: [ProviderSnapshot.Provider: ComplicationWindowChoice], in defaults: UserDefaults?) {
        defaults?.set(encode(prefs), forKey: ApexGaugeDefaults.complicationWindowsKey)
    }

    public static func decodeHidden(from defaults: UserDefaults?) -> Set<ProviderSnapshot.Provider> {
        guard let data = defaults?.data(forKey: ApexGaugeDefaults.complicationHiddenProvidersKey),
              let raw = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(raw.compactMap(ProviderSnapshot.Provider.init(rawValue:)))
    }

    public static func encodeHidden(_ hidden: Set<ProviderSnapshot.Provider>) -> Data? {
        try? JSONEncoder().encode(hidden.map(\.rawValue).sorted())
    }

    public static func storeHidden(_ hidden: Set<ProviderSnapshot.Provider>, in defaults: UserDefaults?) {
        defaults?.set(encodeHidden(hidden), forKey: ApexGaugeDefaults.complicationHiddenProvidersKey)
    }
}
