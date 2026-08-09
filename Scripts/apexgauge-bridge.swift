#!/usr/bin/env swift

// Apex Gauge Mac bridge.
//
// Claude Code reports subscription quota to exactly one place: the statusline
// payload on stdin (rate_limits.five_hour / .seven_day). Hooks do not carry it
// and OpenTelemetry has no quota metrics, so a statusline shim is the only
// sanctioned capture point. This binary is that shim plus the publisher that
// moves the capture into the app's iCloud container.
//
//   apexgauge-bridge statusline   read stdin, capture, chain to the previous
//                                 statusline command, echo its output
//   apexgauge-bridge publish      copy the local capture into iCloud
//   apexgauge-bridge install      wire settings.json + LaunchAgent
//   apexgauge-bridge uninstall    undo install, restoring any chained command
//   apexgauge-bridge status       report what is wired and how fresh it is

import Foundation

private let bridgeVersion = 1
private let containerID = "iCloud.com.apexaspire.apexgauge"
private let launchAgentLabel = "com.apexaspire.apexgauge.bridge"
private let snapshotFilename = "claude-usage.json"

// MARK: - Paths

private enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Local capture. Written on the statusline hot path, so it stays on a
    /// local volume — never a network or synced one.
    static var supportDirectory: URL {
        home.appendingPathComponent("Library/Application Support/ApexGauge", isDirectory: true)
    }

    static var capture: URL {
        supportDirectory.appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    static var config: URL {
        supportDirectory.appendingPathComponent("bridge-config.json", isDirectory: false)
    }

    /// The ubiquity container as macOS exposes it on disk. The directory is
    /// provisioned by the system once the iOS app has run, so it may be absent
    /// on a Mac whose owner has not launched the app yet.
    static var ubiquityDocuments: URL {
        home
            .appendingPathComponent("Library/Mobile Documents", isDirectory: true)
            .appendingPathComponent(containerID.replacingOccurrences(of: ".", with: "~"), isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
    }

    static var published: URL {
        ubiquityDocuments.appendingPathComponent(snapshotFilename, isDirectory: false)
    }

    static var fableCache: URL {
        supportDirectory.appendingPathComponent("fable-cache.json", isDirectory: false)
    }

    /// Presence of this file enables raw payload retention; see runStatusline.
    static var debugMarker: URL {
        supportDirectory.appendingPathComponent("debug-payload", isDirectory: false)
    }

    static var lastPayload: URL {
        supportDirectory.appendingPathComponent("last-payload.json", isDirectory: false)
    }

    static var claudeSettings: URL {
        home.appendingPathComponent(".claude/settings.json", isDirectory: false)
    }

    static var launchAgent: URL {
        home.appendingPathComponent("Library/LaunchAgents/\(launchAgentLabel).plist", isDirectory: false)
    }
}

// MARK: - Model

/// Mirrors ClaudeBridgeSnapshot on the iOS side. Percentages are "used", to
/// match Claude Code's own vocabulary; the app converts to remaining.
private struct BridgeSnapshot: Codable {
    struct Window: Codable {
        let usedPercent: Double
        let resetsAt: Date?
    }

    let version: Int
    let capturedAt: Date
    let source: String
    let fiveHour: Window?
    let sevenDay: Window?
    /// Only ever populated by the opt-in OAuth probe: Claude Code's status line
    /// does not carry model-scoped windows. Absent means the app shows no Fable
    /// row, which is the intended behaviour when the probe is off.
    var fable: Window?
}

private struct BridgeConfig: Codable {
    /// The statusline command this bridge displaced, restored on uninstall and
    /// executed on every render so an existing statusline keeps working.
    var chainedCommand: String?
    var installedAt: Date
    /// Optional so configs written before the probe existed still decode.
    var fableViaOAuth: Bool?
}

/// Cached result of the OAuth probe, so `publish` — which launchd runs on every
/// capture change — does not hit the network on each invocation.
private struct FableCache: Codable {
    var fetchedAt: Date
    var window: BridgeSnapshot.Window?
}

private func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

private func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

// MARK: - Capture

/// Pulls the two subscription windows out of a statusline payload. Every field
/// is optional by contract: rate_limits appears only for Pro/Max accounts, only
/// after the first API response, and each window can be absent independently.
private func parseRateLimits(_ root: [String: Any]) -> (BridgeSnapshot.Window?, BridgeSnapshot.Window?) {
    guard let limits = root["rate_limits"] as? [String: Any] else {
        return (nil, nil)
    }

    func window(_ key: String) -> BridgeSnapshot.Window? {
        guard let raw = limits[key] as? [String: Any],
              let used = raw["used_percentage"] as? Double
        else {
            return nil
        }
        let resets = (raw["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
        return BridgeSnapshot.Window(usedPercent: used, resetsAt: resets)
    }

    return (window("five_hour"), window("seven_day"))
}

private func writeAtomically(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
}

private func runStatusline() {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    let config = try? makeDecoder().decode(BridgeConfig.self, from: Data(contentsOf: Paths.config))

    // Opt-in diagnostic: retains the raw statusline payload so the fields
    // Claude Code actually sends can be inspected when they change. Off unless
    // the marker exists, because the payload carries cwd and session id.
    if FileManager.default.fileExists(atPath: Paths.debugMarker.path) {
        try? writeAtomically(input, to: Paths.lastPayload)
    }

    // Capture is best-effort and must never break the user's statusline: a
    // throwing capture would leave them staring at an empty status bar with no
    // clue why, so every failure below falls through to the chained command.
    if let root = try? JSONSerialization.jsonObject(with: input) as? [String: Any] {
        let (fiveHour, sevenDay) = parseRateLimits(root)
        if fiveHour != nil || sevenDay != nil {
            let snapshot = BridgeSnapshot(
                version: bridgeVersion,
                capturedAt: Date(),
                source: "claude-code-statusline",
                fiveHour: fiveHour,
                sevenDay: sevenDay)
            if let data = try? makeEncoder().encode(snapshot) {
                try? writeAtomically(data, to: Paths.capture)
                // Fast path. The LaunchAgent re-publishes if this fails because
                // iCloud was not ready yet.
                try? writeAtomically(data, to: Paths.published)
            }
        }
    }

    // Claude Code hides most footer hints once a statusline is configured, so a
    // bridge that printed nothing would cost the user that row for no benefit.
    // With nothing to chain to, render the quota we just captured.
    guard let chained = config?.chainedCommand, !chained.isEmpty else {
        print(defaultStatusLine())
        return
    }
    chainTo(chained, input: input)
}

private func defaultStatusLine() -> String {
    guard let data = try? Data(contentsOf: Paths.capture),
          let snapshot = try? makeDecoder().decode(BridgeSnapshot.self, from: data)
    else {
        return "apexgauge: waiting for usage"
    }

    var parts: [String] = []
    if let five = snapshot.fiveHour {
        parts.append("5h \(Int(five.usedPercent.rounded()))%")
    }
    if let seven = snapshot.sevenDay {
        parts.append("7d \(Int(seven.usedPercent.rounded()))%")
    }
    return parts.isEmpty ? "apexgauge: waiting for usage" : parts.joined(separator: " · ")
}

/// Re-runs the displaced statusline command with the original stdin so its
/// output still reaches Claude Code unchanged.
private func chainTo(_ command: String, input: Data) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]

    let stdin = Pipe()
    process.standardInput = stdin
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError

    guard (try? process.run()) != nil else { return }
    stdin.fileHandleForWriting.write(input)
    try? stdin.fileHandleForWriting.close()
    process.waitUntilExit()
}

// MARK: - Fable probe (opt-in)

private let fableProbeInterval: TimeInterval = 15 * 60
private let usageEndpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

/// Reads the access token Claude Code already maintains, WITHOUT refreshing it.
///
/// This is the deliberate difference from every other client that touches this
/// credential: refreshing rotates the token and kills whichever copy loses the
/// race, which is how Claude Code, CodexBar, and a phone end up fighting over
/// one lineage. An expired token here simply means "skip this cycle" — Claude
/// Code will renew it in its own time.
private func claudeAccessToken() -> String? {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    guard (try? process.run()) != nil else { return nil }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { return nil }

    guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let oauth = root["claudeAiOauth"] as? [String: Any],
          let token = oauth["accessToken"] as? String,
          !token.isEmpty
    else {
        return nil
    }

    // expiresAt is epoch milliseconds. Treat a near-expiry token as unusable
    // rather than risk a 401 that looks like credential trouble.
    if let expiresAt = oauth["expiresAt"] as? Double {
        let expiry = Date(timeIntervalSince1970: expiresAt / 1000)
        guard expiry > Date().addingTimeInterval(60) else { return nil }
    }

    return token
}

private func fetchFableWindow(token: String) -> BridgeSnapshot.Window? {
    var request = URLRequest(url: usageEndpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 20
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
    request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
    request.setValue("application/json", forHTTPHeaderField: "Accept")

    let semaphore = DispatchSemaphore(value: 0)
    var payload: Data?
    URLSession.shared.dataTask(with: request) { data, response, _ in
        if let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) {
            payload = data
        }
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + 25)

    guard let payload,
          let root = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
          let limits = root["limits"] as? [[String: Any]]
    else {
        return nil
    }

    for limit in limits {
        let scope = limit["scope"] as? [String: Any]
        let model = scope?["model"] as? [String: Any]
        let name = (model?["display_name"] as? String) ?? ""
        guard name.lowercased().contains("fable") else { continue }
        guard let used = (limit["percent"] as? Double) ?? (limit["utilization"] as? Double) else { continue }

        var resets: Date?
        if let raw = limit["resets_at"] as? String {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            resets = formatter.date(from: raw) ?? {
                formatter.formatOptions = [.withInternetDateTime]
                return formatter.date(from: raw)
            }()
        }
        return BridgeSnapshot.Window(usedPercent: used, resetsAt: resets)
    }

    return nil
}

/// Returns the Fable window when the probe is enabled, refreshing it at most
/// once per interval. Returns nil — and publishes no Fable row — when disabled.
private func currentFableWindow(config: BridgeConfig?) -> BridgeSnapshot.Window? {
    guard config?.fableViaOAuth == true else { return nil }

    let cache = try? makeDecoder().decode(FableCache.self, from: Data(contentsOf: Paths.fableCache))
    if let cache, Date().timeIntervalSince(cache.fetchedAt) < fableProbeInterval {
        return cache.window
    }

    guard let token = claudeAccessToken() else { return cache?.window }
    let window = fetchFableWindow(token: token)

    // Cache even a nil result: it stops a failing probe retrying every publish.
    if let data = try? makeEncoder().encode(FableCache(fetchedAt: Date(), window: window)) {
        try? writeAtomically(data, to: Paths.fableCache)
    }
    return window ?? cache?.window
}

private func runPublish() {
    guard var data = try? Data(contentsOf: Paths.capture) else {
        FileHandle.standardError.write(Data("apexgauge-bridge: no capture yet\n".utf8))
        exit(1)
    }

    // The Fable window is merged here rather than in the statusline shim: this
    // path is off the render hot path and already rate-limited by launchd.
    let config = try? makeDecoder().decode(BridgeConfig.self, from: Data(contentsOf: Paths.config))
    if let fable = currentFableWindow(config: config),
       var snapshot = try? makeDecoder().decode(BridgeSnapshot.self, from: data)
    {
        snapshot.fable = fable
        if let merged = try? makeEncoder().encode(snapshot) {
            data = merged
        }
    }

    guard FileManager.default.fileExists(atPath: Paths.ubiquityDocuments.deletingLastPathComponent().path) else {
        FileHandle.standardError.write(Data(
            "apexgauge-bridge: iCloud container not provisioned — launch Apex Gauge on the iPhone once, with the same Apple ID, then retry\n".utf8))
        exit(2)
    }

    // Skip an identical rewrite. The LaunchAgent watches the container
    // directory, and our own publish writes into it — without this guard each
    // publish would retrigger the agent indefinitely.
    if let existing = try? Data(contentsOf: Paths.published), existing == data {
        print("unchanged; nothing to publish")
        return
    }

    do {
        try writeAtomically(data, to: Paths.published)
        print("published \(Paths.published.path)")
    } catch {
        FileHandle.standardError.write(Data("apexgauge-bridge: publish failed: \(error.localizedDescription)\n".utf8))
        exit(3)
    }
}

// MARK: - Install

/// Reads settings.json as a generic object so every unrelated key survives the
/// round trip. Claude Code's settings file is hand-maintained and large; a
/// typed model would silently drop whatever it did not know about.
private func loadSettings() throws -> [String: Any] {
    guard let data = try? Data(contentsOf: Paths.claudeSettings) else { return [:] }
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw BridgeError.message("~/.claude/settings.json is not a JSON object.")
    }
    return object
}

private func saveSettings(_ settings: [String: Any]) throws {
    let data = try JSONSerialization.data(
        withJSONObject: settings,
        options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try writeAtomically(data, to: Paths.claudeSettings)
}

private enum BridgeError: Error, LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        }
    }
}

private func executablePath() -> String {
    URL(fileURLWithPath: CommandLine.arguments[0])
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .path
}

private func runInstall() throws {
    let binary = executablePath()
    var settings = try loadSettings()

    // Preserve whatever statusline is already configured. Re-running install
    // must not chain the bridge to itself.
    var chained: String?
    if let existing = settings["statusLine"] as? [String: Any],
       let command = existing["command"] as? String,
       !command.contains("apexgauge-bridge")
    {
        chained = command
    } else if let existing = try? makeDecoder().decode(BridgeConfig.self, from: Data(contentsOf: Paths.config)) {
        chained = existing.chainedCommand
    }

    let config = BridgeConfig(chainedCommand: chained, installedAt: Date())
    try writeAtomically(makeEncoder().encode(config), to: Paths.config)

    settings["statusLine"] = [
        "type": "command",
        "command": "\(binary) statusline",
    ]
    try saveSettings(settings)

    try installLaunchAgent(binary: binary)

    print("Installed:")
    print("  statusline  \(binary) statusline")
    print("  chained     \(chained ?? "(none)")")
    print("  agent       \(Paths.launchAgent.path)")
    print("  capture     \(Paths.capture.path)")
    print("  publishes   \(Paths.published.path)")
}

/// WatchPaths rather than a resident process or a poll loop: the agent is
/// launched by launchd only when the capture actually changes, so it costs
/// nothing while Claude Code is idle but still runs unattended from login.
private func installLaunchAgent(binary: String) throws {
    // Two watches: the local capture (new numbers from Claude Code) and the
    // iCloud container (a refresh request arriving from the iPhone). The
    // container watch is a directory because the request file does not exist
    // until the phone asks; publish's unchanged-content guard is what stops
    // our own writes into that directory from retriggering the agent.
    var watchPaths = [Paths.capture.path]
    if FileManager.default.fileExists(atPath: Paths.ubiquityDocuments.path) {
        watchPaths.append(Paths.ubiquityDocuments.path)
    }

    let plist: [String: Any] = [
        "Label": launchAgentLabel,
        "ProgramArguments": [binary, "publish"],
        "RunAtLoad": true,
        "WatchPaths": watchPaths,
        "ProcessType": "Background",
        "StandardErrorPath": Paths.supportDirectory.appendingPathComponent("bridge.log").path,
    ]

    let data = try PropertyListSerialization.data(
        fromPropertyList: plist, format: .xml, options: 0)
    try writeAtomically(data, to: Paths.launchAgent)

    // bootout first so a re-install replaces cleanly; it fails harmlessly when
    // nothing is loaded yet.
    let uid = getuid()
    shell("/bin/launchctl", ["bootout", "gui/\(uid)/\(launchAgentLabel)"])
    shell("/bin/launchctl", ["bootstrap", "gui/\(uid)", Paths.launchAgent.path])
}

@discardableResult
private func shell(_ path: String, _ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return -1 }
    process.waitUntilExit()
    return process.terminationStatus
}

private func runUninstall() throws {
    let uid = getuid()
    shell("/bin/launchctl", ["bootout", "gui/\(uid)/\(launchAgentLabel)"])
    try? FileManager.default.removeItem(at: Paths.launchAgent)

    var settings = try loadSettings()
    let config = try? makeDecoder().decode(BridgeConfig.self, from: Data(contentsOf: Paths.config))

    if let chained = config?.chainedCommand, !chained.isEmpty {
        settings["statusLine"] = ["type": "command", "command": chained]
    } else if let current = settings["statusLine"] as? [String: Any],
              let command = current["command"] as? String,
              command.contains("apexgauge-bridge")
    {
        settings.removeValue(forKey: "statusLine")
    }
    try saveSettings(settings)
    try? FileManager.default.removeItem(at: Paths.config)
    print("Uninstalled. statusLine restored to: \(config?.chainedCommand ?? "(none)")")
}

private func runFableToggle(_ argument: String?) throws {
    guard let argument, ["on", "off"].contains(argument) else {
        throw BridgeError.message("Usage: apexgauge-bridge fable <on|off>")
    }

    guard var config = try? makeDecoder().decode(BridgeConfig.self, from: Data(contentsOf: Paths.config)) else {
        throw BridgeError.message("Bridge is not installed yet — run: apexgauge-bridge install")
    }

    let enable = argument == "on"
    config.fableViaOAuth = enable
    try writeAtomically(makeEncoder().encode(config), to: Paths.config)
    try? FileManager.default.removeItem(at: Paths.fableCache)

    if enable {
        print("""
        Fable probe ENABLED.

        This calls Anthropic's undocumented usage endpoint with the token Claude
        Code already holds, at most once every \(Int(fableProbeInterval / 60)) minutes. It reads the
        Keychain but never refreshes the token, so it cannot rotate credentials
        out from under Claude Code.

        This is not an official method and appears nowhere in Anthropic's
        documentation. Anthropic reserves subscription OAuth for Claude Code and
        its own apps and may act on the account without notice. Use at your own
        risk; turn it off with: apexgauge-bridge fable off
        """)
    } else {
        print("Fable probe disabled. Nothing contacts Anthropic; only Claude Code's status line is read.")
    }
}

private func runStatus() {
    let formatter = ISO8601DateFormatter()
    print("bridge version   \(bridgeVersion)")
    print("binary           \(executablePath())")

    if let config = try? makeDecoder().decode(BridgeConfig.self, from: Data(contentsOf: Paths.config)) {
        print("installed at     \(formatter.string(from: config.installedAt))")
        print("chained command  \(config.chainedCommand ?? "(none)")")
        let fableOn = config.fableViaOAuth == true
        print("fable probe      \(fableOn ? "ON — calls Anthropic (unofficial, at own risk)" : "off — status line only")")
    } else {
        print("installed        no (run: apexgauge-bridge install)")
    }

    let agentLoaded = shell("/bin/launchctl", ["print", "gui/\(getuid())/\(launchAgentLabel)"]) == 0
    print("launch agent     \(agentLoaded ? "loaded" : "not loaded")")

    if let data = try? Data(contentsOf: Paths.capture),
       let snapshot = try? makeDecoder().decode(BridgeSnapshot.self, from: data)
    {
        let age = Int(Date().timeIntervalSince(snapshot.capturedAt))
        print("capture age      \(age)s")
        if let five = snapshot.fiveHour {
            print("  five_hour      \(five.usedPercent)% used")
        }
        if let seven = snapshot.sevenDay {
            print("  seven_day      \(seven.usedPercent)% used")
        }
    } else {
        print("capture          none yet — run Claude Code once with a Pro/Max account")
    }

    let containerExists = FileManager.default.fileExists(
        atPath: Paths.ubiquityDocuments.deletingLastPathComponent().path)
    print("iCloud container \(containerExists ? "present" : "NOT provisioned — launch Apex Gauge on the iPhone once")")
    print("published        \(FileManager.default.fileExists(atPath: Paths.published.path) ? "yes" : "no")")
}

// MARK: - Entry

private func main() {
    let command = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "status"

    do {
        switch command {
        case "statusline": runStatusline()
        case "publish": runPublish()
        case "install": try runInstall()
        case "uninstall": try runUninstall()
        case "status": runStatus()
        case "fable": try runFableToggle(CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : nil)
        default:
            FileHandle.standardError.write(Data(
                "Usage: apexgauge-bridge <statusline|publish|install|uninstall|status|fable on|off>\n".utf8))
            exit(64)
        }
    } catch {
        FileHandle.standardError.write(Data("apexgauge-bridge: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

main()
