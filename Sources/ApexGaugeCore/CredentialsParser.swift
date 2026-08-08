import Foundation

// MARK: - Coordinator-owned: onboarding parsers + QR connect payload
//
// Parses whatever the user can realistically produce on the Mac into typed
// credentials, so onboarding never requires typing: whole credential files,
// labelled "key: value" text, or bare tokens all work.

public enum CredentialsParser {

    /// Accepts: full ~/.claude/.credentials.json, the inner claudeAiOauth
    /// object, labelled lines ("refreshToken: xxx" / "refresh: xxx"), or a
    /// bare refresh token.
    public static func parseClaude(_ pasted: String) -> ClaudeCredentials? {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let object = jsonObject(in: text) {
            let oauth = (object["claudeAiOauth"] as? [String: Any]) ?? object
            if let refresh = oauth["refreshToken"] as? String, !refresh.isEmpty {
                let access = oauth["accessToken"] as? String ?? ""
                let expiresAt: Date? = (oauth["expiresAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                    ?? (oauth["expiresAt"] as? Int).map { Date(timeIntervalSince1970: Double($0) / 1000) }
                return ClaudeCredentials(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
            }
        }

        if let refresh = labelledValue(in: text, keys: ["refreshToken", "refresh_token", "refresh"]) {
            return ClaudeCredentials(
                accessToken: labelledValue(in: text, keys: ["accessToken", "access_token", "access"]) ?? "",
                refreshToken: refresh)
        }

        // Bare token (Claude Code refresh tokens are single-line secrets).
        if !text.contains(" "), !text.contains("\n"), text.count > 20 {
            return ClaudeCredentials(accessToken: "", refreshToken: text)
        }
        return nil
    }

    /// Accepts: full ~/.codex/auth.json, the inner tokens object, or labelled
    /// lines ("access: xxx" / "refresh: yyy" / "account: zzz").
    public static func parseCodex(_ pasted: String) -> CodexCredentials? {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let object = jsonObject(in: text) {
            let tokens = (object["tokens"] as? [String: Any]) ?? object
            let access = Self.firstString(in: tokens, keys: ["access_token", "accessToken"])
            let refresh = Self.firstString(in: tokens, keys: ["refresh_token", "refreshToken"])
            let account = Self.firstString(in: tokens, keys: ["account_id", "accountId"])
            if let refresh, !refresh.isEmpty {
                return CodexCredentials(accessToken: access ?? "", refreshToken: refresh, accountID: account)
            }
        }

        if let refresh = labelledValue(in: text, keys: ["refresh", "refresh_token", "refreshToken"]) {
            return CodexCredentials(
                accessToken: labelledValue(in: text, keys: ["access", "access_token", "accessToken"]) ?? "",
                refreshToken: refresh,
                accountID: labelledValue(in: text, keys: ["account", "account_id", "accountId"]))
        }
        return nil
    }

    /// A bare Kimi Code API key, trimmed.
    public static func parseKimi(_ pasted: String) -> KimiCredentials? {
        let text = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : KimiCredentials(apiKey: text)
    }

    // MARK: helpers

    private static func jsonObject(in text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else { return nil }
        return dict
    }

    private static func firstString(in dict: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dict[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    /// Matches lines like `refresh: abc123` (case-insensitive key, optional quotes).
    private static func labelledValue(in text: String, keys: [String]) -> String? {
        for line in text.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if keys.contains(where: { $0.lowercased() == key }), !value.isEmpty {
                return value
            }
        }
        return nil
    }
}

// MARK: - QR connect payload
//
// The Mac script (Scripts/qr-connect.swift) renders this as a QR code; the app
// scans it. Claude payloads may also carry the current access token so a scan
// remains usable when refresh-token rotation has invalidated the Mac's copy.
// Codex remains refresh-token-only because its JWT is too large for the QR.

public struct ConnectPayload: Codable, Sendable, Equatable {
    public static let payloadType = "apexgauge-connect"

    public var type: String
    public var provider: String
    public var refreshToken: String
    public var accountID: String?
    public var accessToken: String?
    public var accessTokenExpiresAtMs: Int?

    public init(
        provider: ProviderSnapshot.Provider,
        refreshToken: String,
        accountID: String? = nil,
        accessToken: String? = nil,
        accessTokenExpiresAtMs: Int? = nil
    ) {
        self.type = Self.payloadType
        self.provider = provider.rawValue
        self.refreshToken = refreshToken
        self.accountID = accountID
        self.accessToken = accessToken
        self.accessTokenExpiresAtMs = accessTokenExpiresAtMs
    }

    public func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        return String(decoding: data, as: UTF8.self)
    }

    /// Returns nil when the string is not an ApexGauge connect payload.
    public static func decode(_ string: String) -> ConnectPayload? {
        guard let data = string.data(using: .utf8),
              let payload = try? JSONDecoder().decode(ConnectPayload.self, from: data),
              payload.type == payloadType, !payload.refreshToken.isEmpty
        else { return nil }
        return payload
    }

    public var claudeCredentials: ClaudeCredentials? {
        guard provider == ProviderSnapshot.Provider.claude.rawValue else { return nil }
        return ClaudeCredentials(
            accessToken: accessToken ?? "",
            refreshToken: refreshToken,
            expiresAt: accessTokenExpiresAtMs.map {
                Date(timeIntervalSince1970: TimeInterval($0) / 1_000)
            })
    }

    public var codexCredentials: CodexCredentials? {
        guard provider == ProviderSnapshot.Provider.codex.rawValue else { return nil }
        return CodexCredentials(accessToken: "", refreshToken: refreshToken, accountID: accountID)
    }
}
