import Foundation

/// The payload the Mac bridge publishes into the app's iCloud container.
/// Percentages are "used", matching Claude Code's own `rate_limits` vocabulary;
/// the conversion to remaining happens when mapping to QuotaWindow.
public struct ClaudeBridgeSnapshot: Codable, Sendable, Equatable {
    public struct Window: Codable, Sendable, Equatable {
        public var usedPercent: Double
        public var resetsAt: Date?

        public init(usedPercent: Double, resetsAt: Date? = nil) {
            self.usedPercent = usedPercent
            self.resetsAt = resetsAt
        }
    }

    public static let currentVersion = 1

    public var version: Int
    public var capturedAt: Date
    public var source: String
    public var fiveHour: Window?
    public var sevenDay: Window?
    /// Present only when the Mac bridge's opt-in OAuth probe is enabled;
    /// Claude Code's status line carries no model-scoped windows.
    public var fable: Window?

    public init(
        version: Int = Self.currentVersion,
        capturedAt: Date,
        source: String,
        fiveHour: Window? = nil,
        sevenDay: Window? = nil,
        fable: Window? = nil
    ) {
        self.version = version
        self.capturedAt = capturedAt
        self.source = source
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.fable = fable
    }
}

/// Why the Mac bridge is not currently supplying Claude numbers.
///
/// Modelled explicitly so the UI never has to infer a cause from an absent
/// file. Only causes the phone can actually tell apart are separate cases:
///
/// - The Mac helper writes no capture at all when Claude Code's status line
///   carries no `rate_limits` (non Pro/Max plans, or before the first API
///   response of a session). On the phone that is byte-for-byte the same as
///   "helper never installed" and "Claude Code not run yet", so all three share
///   `.noCapture` and its copy names every possibility instead of guessing.
/// - A stale capture is not a state here: it is healthy data and stays a
///   `capturedAt` matter.
///
/// Raw values are the wire format (carried inside `ProviderSnapshot`), so new
/// cases must be additive; an unknown value decodes to nil on older builds.
public enum ClaudeBridgeState: String, Codable, Sendable, Equatable, CaseIterable {
    /// Signed out of iCloud, iCloud Drive off, or the container is not provisioned.
    case iCloudUnavailable
    /// The container is reachable but holds no snapshot file.
    case noCapture
    /// A snapshot file exists but carries neither window.
    case noWindows

    /// Short heading, matching the vocabulary of the Settings bridge row.
    public var title: String {
        switch self {
        case .iCloudUnavailable: "iCloud unavailable"
        case .noCapture: "Waiting for the Mac bridge"
        case .noWindows: "Bridge has no usage figures"
        }
    }

    /// Actionable one-or-two sentence explanation for the dashboard card.
    public var detail: String {
        switch self {
        case .iCloudUnavailable:
            "Sign in to iCloud and turn on iCloud Drive for Apex Gauge on this iPhone."
        case .noCapture:
            "Install the Mac bridge, then use Claude Code on a Pro or Max plan. Usage only appears after Claude Code's first reply in a session."
        case .noWindows:
            "Claude Code sent no usage figures. They appear only on Pro and Max plans, after the first reply in a session."
        }
    }

    /// Terse text for the watch, which has no room for the dashboard copy.
    public var watchText: String {
        switch self {
        case .iCloudUnavailable: "iPhone iCloud is off"
        case .noCapture: "Bridge idle"
        case .noWindows: "Bridge idle: no usage sent"
        }
    }
}

/// What one read of the bridge produced, before it is flattened into a
/// `ProviderSnapshot`. Keeps "no data and why" distinct from "data".
public enum ClaudeBridgeReading: Sendable, Equatable {
    case available(ClaudeBridgeSnapshot)
    case unavailable(ClaudeBridgeState)
}

/// Reads Claude subscription quota from the Mac bridge instead of calling
/// Anthropic directly. Claude Code hands these numbers to its own statusline;
/// the bridge captures them there and publishes through iCloud, so the phone
/// never holds Claude credentials and never impersonates the CLI.
///
/// Deliberately narrower than `ClaudeUsageFetcher`: the statusline payload
/// carries only the five-hour and seven-day windows, so the Opus, Sonnet, and
/// Fable model-scoped windows are not available on this path.
public struct ClaudeBridgeFetcher: UsageFetching {
    public let provider: ProviderSnapshot.Provider = .claude

    /// Capture older than this is still shown — quota does not move while
    /// Claude Code is idle — but is called out so a dead bridge cannot
    /// masquerade as a quiet day.
    public static let staleCaptureThreshold: TimeInterval = 6 * 60 * 60

    public static let snapshotFilename = "claude-usage.json"
    public static let containerID = "iCloud.com.apexaspire.apexgauge"

    private let locateContainer: @Sendable () -> URL?
    private let readData: @Sendable (URL) throws -> Data
    private let now: @Sendable () -> Date

    public init(
        locateContainer: @escaping @Sendable () -> URL? = { ClaudeBridgeFetcher.defaultContainerURL() },
        readData: @escaping @Sendable (URL) throws -> Data = { try Data(contentsOf: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.locateContainer = locateContainer
        self.readData = readData
        self.now = now
    }

    /// Resolving a ubiquity container hits the CloudDocs daemon and can block,
    /// so callers must stay off the main thread. Returns nil when the user is
    /// signed out of iCloud or the container has not been provisioned.
    public static func defaultContainerURL() -> URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: containerID)?
            .appendingPathComponent("Documents", isDirectory: true)
    }

    /// Reads the bridge once and reports what it found. Throws only for a file
    /// that exists but cannot be understood (decoding / newer version); every
    /// "nothing to show" case is a `.unavailable` reading rather than an error.
    public func read() throws -> ClaudeBridgeReading {
        guard let documents = self.locateContainer() else {
            return .unavailable(.iCloudUnavailable)
        }

        let fileURL = documents.appendingPathComponent(Self.snapshotFilename, isDirectory: false)

        // A published file arrives as a metadata stub until it is pulled down.
        // Requesting the download is harmless when the file is already local.
        try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)

        let data: Data
        do {
            data = try self.readData(fileURL)
        } catch {
            return .unavailable(.noCapture)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot: ClaudeBridgeSnapshot
        do {
            snapshot = try decoder.decode(ClaudeBridgeSnapshot.self, from: data)
        } catch {
            throw UsageFetchError.decoding("Bridge snapshot unreadable: \(error.localizedDescription)")
        }

        guard snapshot.version <= ClaudeBridgeSnapshot.currentVersion else {
            throw UsageFetchError.decoding(
                "Bridge snapshot v\(snapshot.version) is newer than this app understands.")
        }

        guard snapshot.fiveHour != nil || snapshot.sevenDay != nil || snapshot.fable != nil else {
            return .unavailable(.noWindows)
        }
        return .available(snapshot)
    }

    public func fetchUsage() async throws -> ProviderSnapshot {
        let snapshot: ClaudeBridgeSnapshot
        switch try self.read() {
        case let .unavailable(state):
            // Not an error: the bridge state travels as data so every surface
            // can say what to do, instead of "Not configured".
            return ProviderSnapshot(
                provider: .claude,
                windows: [],
                fetchedAt: self.now(),
                lastError: nil,
                capturedAt: nil,
                bridgeState: state)
        case let .available(value):
            snapshot = value
        }

        var windows: [QuotaWindow] = []
        if let fiveHour = snapshot.fiveHour {
            windows.append(QuotaWindow(
                kind: .session,
                remainingPercent: ProviderSupport.remainingPercent(fromUsed: fiveHour.usedPercent),
                resetsAt: fiveHour.resetsAt))
        }
        if let sevenDay = snapshot.sevenDay {
            windows.append(QuotaWindow(
                kind: .weekly,
                remainingPercent: ProviderSupport.remainingPercent(fromUsed: sevenDay.usedPercent),
                resetsAt: sevenDay.resetsAt))
        }
        if let fable = snapshot.fable {
            windows.append(QuotaWindow(
                kind: .fable,
                remainingPercent: ProviderSupport.remainingPercent(fromUsed: fable.usedPercent),
                resetsAt: fable.resetsAt))
        }

        // fetchedAt is when the app read the bridge, not when the Mac captured:
        // the complication's staleness check drives its refresh cadence, and
        // feeding it an idle capture time would pin it to permanent refresh.
        // capturedAt carries the real measurement time so no surface can
        // present a read as though it were a fresh measurement.
        return ProviderSnapshot(
            provider: .claude,
            windows: windows,
            fetchedAt: self.now(),
            lastError: nil,
            capturedAt: snapshot.capturedAt)
    }
}
