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

    public func fetchUsage() async throws -> ProviderSnapshot {
        guard let documents = self.locateContainer() else {
            throw UsageFetchError.notConfigured
        }

        let fileURL = documents.appendingPathComponent(Self.snapshotFilename, isDirectory: false)

        // A published file arrives as a metadata stub until it is pulled down.
        // Requesting the download is harmless when the file is already local.
        try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)

        let data: Data
        do {
            data = try self.readData(fileURL)
        } catch {
            throw UsageFetchError.notConfigured
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

        guard !windows.isEmpty else {
            throw UsageFetchError.notConfigured
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
