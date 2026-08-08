import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import ApexGaugeCore

enum TestFailure: Error {
    case missingHTTPResponse
    case intentional
}

actor StubHTTPClient: HTTPClient {
    struct Response {
        let status: Int
        let headers: [String: String]
        let data: Data

        init(status: Int = 200, headers: [String: String] = [:], json: String) {
            self.status = status
            self.headers = headers
            self.data = Data(json.utf8)
        }
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(_ responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        self.requests.append(request)
        guard !self.responses.isEmpty else { throw TestFailure.missingHTTPResponse }
        let response = self.responses.removeFirst()
        let httpResponse = HTTPURLResponse(
            url: request.url!,
            statusCode: response.status,
            httpVersion: nil,
            headerFields: response.headers)!
        return (response.data, httpResponse)
    }

    func recordedRequests() -> [URLRequest] {
        self.requests
    }
}

actor MockCredentialStore: CredentialStore {
    private var claude: ClaudeCredentials?
    private var codex: CodexCredentials?
    private var kimi: KimiCredentials?
    private var savedClaudeValues: [ClaudeCredentials] = []
    private var savedCodexValues: [CodexCredentials] = []

    init(
        claude: ClaudeCredentials? = nil,
        codex: CodexCredentials? = nil,
        kimi: KimiCredentials? = nil
    ) {
        self.claude = claude
        self.codex = codex
        self.kimi = kimi
    }

    func loadClaude() async throws -> ClaudeCredentials? { self.claude }
    func loadCodex() async throws -> CodexCredentials? { self.codex }
    func loadKimi() async throws -> KimiCredentials? { self.kimi }

    func saveClaude(_ credentials: ClaudeCredentials) async throws {
        self.claude = credentials
        self.savedClaudeValues.append(credentials)
    }

    func saveCodex(_ credentials: CodexCredentials) async throws {
        self.codex = credentials
        self.savedCodexValues.append(credentials)
    }

    func saveKimi(_ credentials: KimiCredentials) async throws {
        self.kimi = credentials
    }

    func clear(provider: ProviderSnapshot.Provider) async throws {
        switch provider {
        case .claude: self.claude = nil
        case .codex: self.codex = nil
        case .kimi: self.kimi = nil
        }
    }

    func savedClaude() -> [ClaudeCredentials] { self.savedClaudeValues }
    func savedCodex() -> [CodexCredentials] { self.savedCodexValues }
}

func makeJWT(expiration: Date) throws -> String {
    let payload = try JSONSerialization.data(withJSONObject: ["exp": expiration.timeIntervalSince1970])
    let encoded = payload.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "header.\(encoded).signature"
}
