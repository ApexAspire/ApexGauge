#!/usr/bin/env swift

import Foundation
import CoreImage
import AppKit

private let payloadType = "apexgauge-connect"
private let maximumClaudePayloadBytes = 2_500
private let securityNotice = "QR closed. Nothing was written to disk. The token grants API access until revoked — regenerate provider credentials if the code was photographed or shared."

private enum ScriptError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message): message
        }
    }
}

private struct ConnectPayload: Codable {
    let type: String
    let provider: String
    let refreshToken: String
    let accountID: String?
    let accessToken: String?
    let accessTokenExpiresAtMs: Int?

    init(
        provider: String,
        refreshToken: String,
        accountID: String? = nil,
        accessToken: String? = nil,
        accessTokenExpiresAtMs: Int? = nil
    ) {
        self.type = payloadType
        self.provider = provider
        self.refreshToken = refreshToken
        self.accountID = accountID
        self.accessToken = accessToken
        self.accessTokenExpiresAtMs = accessTokenExpiresAtMs
    }
}

private struct ClaudeCredentialFile: Decodable {
    struct OAuth: Decodable {
        let refreshToken: String
        let accessToken: String?
        let expiresAt: Int?
    }

    let claudeAiOauth: OAuth
}

private struct CodexCredentialFile: Decodable {
    struct Tokens: Decodable {
        let refreshToken: String
        let accountID: String?

        enum CodingKeys: String, CodingKey {
            case refreshToken = "refresh_token"
            case accountID = "account_id"
        }
    }

    let tokens: Tokens
}

private func usage() {
    fputs("Usage: swift Scripts/qr-connect.swift <claude|codex|--selftest>\n", stderr)
}

private func encode(_ payload: ConnectPayload) throws -> (data: Data, string: String) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(payload)
    guard let string = String(data: data, encoding: .utf8) else {
        throw ScriptError.message("Could not encode the connect payload as UTF-8.")
    }
    return (data, string)
}

private func claudePayload() throws -> (payload: ConnectPayload, omittedAccessToken: Bool) {
    // The Keychain item is the Claude Code CLI's live credential store on
    // macOS (it is what CodexBar reads first); ~/.claude/.credentials.json
    // can be months stale and hold a rotated-dead refresh token. Keychain
    // first — note this may trigger a one-time keychain access prompt.
    let data: Data
    do {
        data = try claudeCredentialsFromKeychain()
    } catch {
        let credentialsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json", isDirectory: false)
        do {
            data = try Data(contentsOf: credentialsURL)
        } catch {
            throw ScriptError.message("Claude credentials were unavailable from both the Keychain and the credential file.")
        }
    }

    let credentials: ClaudeCredentialFile
    do {
        credentials = try JSONDecoder().decode(ClaudeCredentialFile.self, from: data)
    } catch {
        throw ScriptError.message("Claude credentials JSON does not contain claudeAiOauth.refreshToken.")
    }
    guard !credentials.claudeAiOauth.refreshToken.isEmpty else {
        throw ScriptError.message("Claude refresh token is empty.")
    }
    let accessToken = credentials.claudeAiOauth.accessToken.flatMap { $0.isEmpty ? nil : $0 }
    let payload = ConnectPayload(
        provider: "claude",
        refreshToken: credentials.claudeAiOauth.refreshToken,
        accessToken: accessToken,
        accessTokenExpiresAtMs: credentials.claudeAiOauth.expiresAt)
    if accessToken != nil, try encode(payload).data.count > maximumClaudePayloadBytes {
        return (
            ConnectPayload(
                provider: "claude",
                refreshToken: credentials.claudeAiOauth.refreshToken,
                accessTokenExpiresAtMs: credentials.claudeAiOauth.expiresAt),
            true)
    }
    return (payload, false)
}

private func claudeCredentialsFromKeychain() throws -> Data {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
    process.standardOutput = output

    do {
        try process.run()
    } catch {
        throw ScriptError.message("Could not run /usr/bin/security for Claude credentials.")
    }

    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0, !data.isEmpty else {
        throw ScriptError.message("Claude credentials were unavailable from both the credential file and Keychain.")
    }
    return data
}

private func codexPayload() throws -> ConnectPayload {
    let environment = ProcessInfo.processInfo.environment
    let codexHome: URL
    if let configured = environment["CODEX_HOME"], !configured.isEmpty {
        codexHome = URL(fileURLWithPath: (configured as NSString).expandingTildeInPath, isDirectory: true)
    } else {
        codexHome = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }
    let credentialsURL = codexHome.appendingPathComponent("auth.json", isDirectory: false)

    let data: Data
    do {
        data = try Data(contentsOf: credentialsURL)
    } catch {
        throw ScriptError.message("Could not read Codex credentials at \(credentialsURL.path).")
    }

    let credentials: CodexCredentialFile
    do {
        credentials = try JSONDecoder().decode(CodexCredentialFile.self, from: data)
    } catch {
        throw ScriptError.message("Codex credentials JSON does not contain tokens.refresh_token.")
    }
    guard !credentials.tokens.refreshToken.isEmpty else {
        throw ScriptError.message("Codex refresh token is empty.")
    }
    let accountID = credentials.tokens.accountID.flatMap { $0.isEmpty ? nil : $0 }
    return ConnectPayload(
        provider: "codex",
        refreshToken: credentials.tokens.refreshToken,
        accountID: accountID)
}

private func renderQRCode(_ payload: String) throws -> CGImage {
    guard let message = payload.data(using: .utf8),
          let filter = CIFilter(name: "CIQRCodeGenerator")
    else {
        throw ScriptError.message("Could not initialize the QR generator.")
    }
    filter.setValue(message, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let qrImage = filter.outputImage else {
        throw ScriptError.message("Core Image did not produce a QR image.")
    }

    let moduleSide = max(qrImage.extent.width, qrImage.extent.height)
    let scale = max(1, floor(280 / moduleSide))
    let scaled = qrImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let extent = scaled.extent.integral
    let whiteBackground = CIImage(color: .white).cropped(to: extent)
    let composited = scaled.composited(over: whiteBackground)

    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let cgImage = context.createCGImage(composited, from: extent) else {
        throw ScriptError.message("Could not rasterize the QR image.")
    }
    return cgImage
}

private func decodeQRCode(_ cgImage: CGImage) throws -> String {
    let image = CIImage(cgImage: cgImage)
    let detector = CIDetector(
        ofType: CIDetectorTypeQRCode,
        context: CIContext(),
        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    guard let feature = detector?.features(in: image).compactMap({ $0 as? CIQRCodeFeature }).first,
          let message = feature.messageString
    else {
        throw ScriptError.message("Self-test could not decode the generated QR code.")
    }
    return message
}

private func runSelfTest() throws {
    let payload = ConnectPayload(
        provider: "claude",
        refreshToken: "selftest-refresh-token",
        accessToken: "selftest-access-token",
        accessTokenExpiresAtMs: 1_890_000_000_000)
    let encoded = try encode(payload)
    let cgImage = try renderQRCode(encoded.string)
    let decoded = try decodeQRCode(cgImage)
    guard decoded == encoded.string,
          let decodedData = decoded.data(using: .utf8),
          let object = try JSONSerialization.jsonObject(with: decodedData) as? [String: Any],
          Set(object.keys) == Set([
              "type", "provider", "refreshToken", "accessToken", "accessTokenExpiresAtMs",
          ]),
          object["type"] as? String == payloadType,
          object["provider"] as? String == "claude",
          object["refreshToken"] as? String == "selftest-refresh-token",
          object["accessToken"] as? String == "selftest-access-token",
          object["accessTokenExpiresAtMs"] as? Int == 1_890_000_000_000
    else {
        throw ScriptError.message("Self-test payload did not round-trip with the exact connect keys.")
    }
    print("SELFTEST OK \(encoded.data.count) payload bytes")
}

private final class QRWindow: NSWindow {
    override var canBecomeKey: Bool { true }

    override func performClose(_ sender: Any?) {
        close()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
        } else {
            super.keyDown(with: event)
        }
    }
}

private final class QRDisplaySession: NSObject, NSWindowDelegate, @unchecked Sendable {
    private let application: NSApplication
    private var imageView: NSImageView?
    private var window: NSWindow?
    private var stopping = false

    private(set) var exitCode: Int32 = 0

    init(application: NSApplication, cgImage: CGImage) {
        self.application = application
        super.init()

        let windowSide: CGFloat = 340
        let imageSide: CGFloat = 280
        let imageOrigin = (windowSide - imageSide) / 2
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: windowSide, height: windowSide))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.white.cgColor

        let imageView = NSImageView(frame: NSRect(
            x: imageOrigin,
            y: imageOrigin,
            width: imageSide,
            height: imageSide))
        imageView.image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height))
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleNone
        imageView.wantsLayer = true
        imageView.layer?.magnificationFilter = .nearest
        imageView.layer?.minificationFilter = .nearest
        contentView.addSubview(imageView)
        self.imageView = imageView

        let closeButton = NSButton(frame: NSRect(x: windowSide - 30, y: windowSide - 30, width: 22, height: 22))
        closeButton.title = "×"
        closeButton.toolTip = "Close QR code"
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 18, weight: .medium)
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeRequested(_:))
        contentView.addSubview(closeButton)

        let window = QRWindow(
            contentRect: contentView.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false)
        window.title = "Apex Gauge — scan from iPhone"
        window.contentView = contentView
        window.backgroundColor = .white
        window.isOpaque = true
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        window.center()
        self.window = window
    }

    func show() {
        window?.makeKeyAndOrderFront(nil)
        application.activate(ignoringOtherApps: true)
    }

    @objc private func closeRequested(_ sender: Any?) {
        window?.close()
    }

    func windowWillClose(_ notification: Notification) {
        stop(exitCode: 0)
    }

    func stop(exitCode: Int32) {
        precondition(Thread.isMainThread)
        guard !stopping else { return }
        stopping = true
        self.exitCode = exitCode

        imageView?.image = nil
        imageView = nil
        window?.delegate = nil
        window?.orderOut(nil)
        window?.contentView = nil
        window = nil

        application.stop(nil)
        application.postEvent(
            NSEvent.otherEvent(
                with: .applicationDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 0,
                data1: 0,
                data2: 0)!,
            atStart: false)
    }
}

private func installSignalCleanup(for session: QRDisplaySession) -> [DispatchSourceSignal] {
    [SIGINT, SIGTERM, SIGHUP, SIGQUIT].map { signalNumber in
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler {
            session.stop(exitCode: 128 + signalNumber)
        }
        source.resume()
        return source
    }
}

private func runProvider(_ provider: String) throws {
    let payload: ConnectPayload
    let omittedClaudeAccessToken: Bool
    switch provider {
    case "claude":
        let result = try claudePayload()
        payload = result.payload
        omittedClaudeAccessToken = result.omittedAccessToken
    case "codex":
        payload = try codexPayload()
        omittedClaudeAccessToken = false
    default: throw ScriptError.message("Unsupported provider.")
    }

    let encoded = try encode(payload)
    let cgImage = try renderQRCode(encoded.string)

    print("Provider: \(provider)")
    print("Payload bytes: \(encoded.data.count)")
    if omittedClaudeAccessToken {
        print("Claude access token omitted: payload would exceed \(maximumClaudePayloadBytes) bytes.")
    }
    print("Nothing is written to disk. Press Return in this terminal or close the QR window when finished.")

    let application = NSApplication.shared
    application.setActivationPolicy(.accessory)
    let session = QRDisplaySession(application: application, cgImage: cgImage)
    let signalSources = installSignalCleanup(for: session)
    session.show()

    DispatchQueue.global(qos: .userInitiated).async {
        _ = readLine()
        DispatchQueue.main.async {
            session.stop(exitCode: 0)
        }
    }

    application.run()
    signalSources.forEach { $0.cancel() }
    print(securityNotice)
    if session.exitCode != 0 {
        exit(session.exitCode)
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 1 else {
    usage()
    exit(64)
}

do {
    if arguments[0] == "--selftest" {
        try runSelfTest()
    } else if arguments[0] == "claude" || arguments[0] == "codex" {
        try runProvider(arguments[0])
    } else {
        usage()
        exit(64)
    }
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
