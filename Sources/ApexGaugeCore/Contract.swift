import Foundation

// MARK: - Coordinator-owned API contract
//
// This file is owned by the coordinator (main thread). Workers building the
// provider fetchers (Sources/ApexGaugeCore/Providers/**) and the iOS app
// (App/**) must code against these types and must NOT modify this file.
// If the contract is insufficient, report back instead of changing it.

// MARK: Credentials

/// Claude Code OAuth credentials (subscription quota path).
/// Source of truth off-device: macOS Keychain item "Claude Code-credentials"
/// or ~/.claude/.credentials.json (paste-onboarding takes refreshToken).
public struct ClaudeCredentials: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date?

    public init(accessToken: String, refreshToken: String, expiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// Codex/ChatGPT OAuth credentials. Refresh tokens ROTATE: this app is the
/// sole refresh owner, so saveCodex must be called with every rotated pair.
/// Source of truth off-device: ~/.codex/auth.json.
public struct CodexCredentials: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var accountID: String?

    public init(accessToken: String, refreshToken: String, accountID: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountID = accountID
    }
}

/// Kimi Code API key (official, user-created in the Kimi Code Console).
public struct KimiCredentials: Codable, Sendable, Equatable {
    public var apiKey: String

    public init(apiKey: String) {
        self.apiKey = apiKey
    }
}

/// Implemented app-side (iOS Keychain). The core only depends on the protocol.
/// Fetchers persist rotated/refreshed tokens through this store after every
/// successful refresh — that is what keeps the phone the sole refresh owner.
public protocol CredentialStore: Sendable {
    func loadClaude() async throws -> ClaudeCredentials?
    func saveClaude(_ credentials: ClaudeCredentials) async throws
    func loadCodex() async throws -> CodexCredentials?
    func saveCodex(_ credentials: CodexCredentials) async throws
    func loadKimi() async throws -> KimiCredentials?
    func saveKimi(_ credentials: KimiCredentials) async throws
    /// Remove all stored credentials for a provider (onboarding "disconnect").
    func clear(provider: ProviderSnapshot.Provider) async throws
}

// MARK: Fetching

public enum UsageFetchError: Error, Sendable, Equatable {
    /// No credentials stored for this provider.
    case notConfigured
    /// 401/403 from the provider — credentials rejected, needs re-onboarding.
    case unauthorized
    /// 429. retryAfter is the server-provided delay when parseable.
    case rateLimited(retryAfter: TimeInterval?)
    /// Any other non-2xx response. body truncated to ~500 chars.
    case http(status: Int, body: String)
    case decoding(String)
    case network(String)
}

/// One fetcher per provider. Implementations live in
/// Sources/ApexGaugeCore/Providers/<Name>/ and are vendored-adapted from
/// CodexBar's CodexBarCore (see docs/plan.md for source files).
///
/// Contract for implementers:
/// - If the stored access token is expired/missing, refresh FIRST using the
///   stored refresh token, persist rotated tokens via the store, then fetch.
/// - Refresh endpoints + client IDs (public, from CodexBar):
///     Claude: POST https://platform.claude.com/v1/oauth/token
///             client_id 9d1c250a-e61b-44d9-88ed-5944d1962f5e
///     Codex:  POST https://auth.openai.com/oauth/token
///             client_id app_EMoamEEZ73f0CkXaXp7hrann
/// - Usage endpoints:
///     Claude: GET https://api.anthropic.com/api/oauth/usage
///             headers: Authorization Bearer, anthropic-beta: oauth-2025-04-20,
///             User-Agent: claude-code/2.1.0
///     Codex:  GET https://chatgpt.com/backend-api/wham/usage
///             headers: Authorization Bearer, ChatGPT-Account-Id when set
///     Kimi:   GET https://api.kimi.com/coding/v1/usages
///             header: Authorization Bearer <apiKey>
/// - Map provider responses onto ProviderSnapshot/QuotaWindow (Snapshot.swift):
///     Claude five_hour -> .session, seven_day -> .weekly,
///     seven_day_sonnet/opus -> .weekly (title via window kind .other if both
///     present), limits[] model-scoped "fable" entry -> .fable.
///     Codex primary_window -> .session, secondary_window -> .weekly.
///     Kimi weekly quota -> .weekly, 5h rate-limit window -> .session.
/// - Convert used% to remaining% (100 - used) when mapping.
/// - Honor Retry-After on 429 and surface .rateLimited.
public protocol UsageFetching: Sendable {
    var provider: ProviderSnapshot.Provider { get }
    func fetchUsage() async throws -> ProviderSnapshot
}

/// Fan-out engine used by the app: refreshes every configured provider and
/// assembles a UsageSnapshot. A provider that throws contributes a
/// ProviderSnapshot carrying lastError (never fail the whole snapshot because
/// one provider is down).
public protocol UsageEngineing: Sendable {
    func refreshAll() async -> UsageSnapshot
}
