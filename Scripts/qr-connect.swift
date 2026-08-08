#!/usr/bin/env swift

import Foundation
import CoreImage
import AppKit

private let payloadType = "apexgauge-connect"
private let deletionNotice = "QR deleted. The token grants API access until revoked — regenerate provider credentials if the image leaked."

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

    init(provider: String, refreshToken: String, accountID: String? = nil) {
        self.type = payloadType
        self.provider = provider
        self.refreshToken = refreshToken
        self.accountID = accountID
    }
}

private struct ClaudeCredentialFile: Decodable {
    struct OAuth: Decodable {
        let refreshToken: String
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

private final class TemporaryQR: @unchecked Sendable {
    let directoryURL: URL
    let pngURL: URL

    private let lock = NSLock()
    private var deleted = false

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
        self.pngURL = directoryURL.appendingPathComponent("connect.png", isDirectory: false)
    }

    func delete(printNotice: Bool) throws {
        lock.lock()
        guard !deleted else {
            lock.unlock()
            return
        }

        do {
            try FileManager.default.removeItem(at: directoryURL)
            deleted = true
            lock.unlock()
        } catch {
            lock.unlock()
            throw ScriptError.message("Could not delete the private QR directory at \(directoryURL.path).")
        }
        if printNotice {
            print(deletionNotice)
        }
    }
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

private func claudePayload() throws -> ConnectPayload {
    let credentialsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/.credentials.json", isDirectory: false)

    let data: Data
    do {
        data = try Data(contentsOf: credentialsURL)
    } catch {
        data = try claudeCredentialsFromKeychain()
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
    return ConnectPayload(provider: "claude", refreshToken: credentials.claudeAiOauth.refreshToken)
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

private func makePrivateTemporaryDirectory() throws -> URL {
    let templatePath = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("apexgaugeqr-XXXXXX")
    var template = Array(templatePath.utf8CString)
    let createdPath: String? = template.withUnsafeMutableBufferPointer { buffer in
        guard let pointer = mkdtemp(buffer.baseAddress) else { return nil }
        return String(cString: pointer)
    }
    guard let createdPath else {
        throw ScriptError.message("Could not create a private temporary directory for the QR code.")
    }
    return URL(fileURLWithPath: createdPath, isDirectory: true)
}

private func renderQRCode(_ payload: String) throws -> TemporaryQR {
    let temporaryQR = TemporaryQR(directoryURL: try makePrivateTemporaryDirectory())
    do {
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
        let scale = max(1, floor(512 / moduleSide))
        let scaled = qrImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = scaled.extent.integral
        let whiteBackground = CIImage(color: .white).cropped(to: extent)
        let composited = scaled.composited(over: whiteBackground)

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(composited, from: extent) else {
            throw ScriptError.message("Could not rasterize the QR image.")
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ScriptError.message("Could not encode the QR image as PNG.")
        }
        try pngData.write(to: temporaryQR.pngURL, options: .atomic)
        return temporaryQR
    } catch {
        try? temporaryQR.delete(printNotice: false)
        throw error
    }
}

private func decodeQRCode(at url: URL) throws -> String {
    guard let image = CIImage(contentsOf: url) else {
        throw ScriptError.message("Self-test could not read the generated PNG.")
    }
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
        provider: "codex",
        refreshToken: "selftest-refresh-token",
        accountID: "selftest-account-id")
    let encoded = try encode(payload)
    let temporaryQR = try renderQRCode(encoded.string)

    do {
        let decoded = try decodeQRCode(at: temporaryQR.pngURL)
        guard decoded == encoded.string,
              let decodedData = decoded.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: decodedData) as? [String: Any],
              Set(object.keys) == Set(["type", "provider", "refreshToken", "accountID"]),
              object["type"] as? String == payloadType,
              object["provider"] as? String == "codex",
              object["refreshToken"] as? String == "selftest-refresh-token",
              object["accountID"] as? String == "selftest-account-id"
        else {
            throw ScriptError.message("Self-test payload did not round-trip with the exact connect keys.")
        }
        try temporaryQR.delete(printNotice: false)
        print("SELFTEST OK \(encoded.data.count) payload bytes")
    } catch {
        try? temporaryQR.delete(printNotice: false)
        throw error
    }
}

private func installSignalCleanup(for temporaryQR: TemporaryQR) -> [DispatchSourceSignal] {
    [SIGINT, SIGTERM, SIGHUP, SIGQUIT].map { signalNumber in
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .global())
        source.setEventHandler {
            do {
                try temporaryQR.delete(printNotice: true)
                exit(128 + signalNumber)
            } catch {
                fputs("Error: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        }
        source.resume()
        return source
    }
}

private func runProvider(_ provider: String) throws {
    let payload: ConnectPayload
    switch provider {
    case "claude": payload = try claudePayload()
    case "codex": payload = try codexPayload()
    default: throw ScriptError.message("Unsupported provider.")
    }

    let encoded = try encode(payload)
    let temporaryQR = try renderQRCode(encoded.string)
    let signalSources = installSignalCleanup(for: temporaryQR)

    print("Provider: \(provider)")
    print("Payload bytes: \(encoded.data.count)")
    print("PNG path: \(temporaryQR.pngURL.path)")

    guard NSWorkspace.shared.open(temporaryQR.pngURL) else {
        try temporaryQR.delete(printNotice: true)
        throw ScriptError.message("Could not open the generated QR PNG.")
    }

    _ = readLine()
    try temporaryQR.delete(printNotice: true)
    signalSources.forEach { $0.cancel() }
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
