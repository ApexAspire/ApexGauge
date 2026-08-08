import XCTest
@testable import ApexGaugeCore

final class CredentialsParserTests: XCTestCase {
    // MARK: Claude

    func testClaudeFullCredentialsFile() {
        let pasted = """
        {"claudeAiOauth":{"accessToken":"acc-123","refreshToken":"ref-456","expiresAt":1890000000000,"scopes":["user:profile"]}}
        """
        let creds = CredentialsParser.parseClaude(pasted)
        XCTAssertEqual(creds?.refreshToken, "ref-456")
        XCTAssertEqual(creds?.accessToken, "acc-123")
        XCTAssertEqual(creds?.expiresAt, Date(timeIntervalSince1970: 1_890_000_000))
    }

    func testClaudeLabelledLines() {
        let pasted = "access: acc-123\nrefresh: ref-456"
        let creds = CredentialsParser.parseClaude(pasted)
        XCTAssertEqual(creds?.refreshToken, "ref-456")
        XCTAssertEqual(creds?.accessToken, "acc-123")
    }

    func testClaudeBareRefreshToken() {
        let creds = CredentialsParser.parseClaude("sk-ant-oat01-abcdef1234567890abcdef")
        XCTAssertEqual(creds?.refreshToken, "sk-ant-oat01-abcdef1234567890abcdef")
        XCTAssertEqual(creds?.accessToken, "")
    }

    func testClaudeRejectsGarbage() {
        XCTAssertNil(CredentialsParser.parseClaude(""))
        XCTAssertNil(CredentialsParser.parseClaude("hello world, this is not a token"))
    }

    // MARK: Codex

    func testCodexFullAuthFile() {
        let pasted = """
        {"tokens":{"access_token":"acc-123","refresh_token":"ref-456","account_id":"acct-789","id_token":"id-x"},"last_refresh":"2026-08-08T00:00:00Z"}
        """
        let creds = CredentialsParser.parseCodex(pasted)
        XCTAssertEqual(creds?.accessToken, "acc-123")
        XCTAssertEqual(creds?.refreshToken, "ref-456")
        XCTAssertEqual(creds?.accountID, "acct-789")
    }

    func testCodexLabelledLines() {
        let pasted = "access: acc-123\nrefresh: ref-456\naccount: acct-789"
        let creds = CredentialsParser.parseCodex(pasted)
        XCTAssertEqual(creds?.refreshToken, "ref-456")
        XCTAssertEqual(creds?.accountID, "acct-789")
    }

    func testCodexRejectsGarbage() {
        XCTAssertNil(CredentialsParser.parseCodex(""))
        XCTAssertNil(CredentialsParser.parseCodex("{}"))
    }

    // MARK: Kimi

    func testKimiTrimsWhitespace() {
        XCTAssertEqual(CredentialsParser.parseKimi("  sk-kimi-key \n")?.apiKey, "sk-kimi-key")
        XCTAssertNil(CredentialsParser.parseKimi("   "))
    }

    // MARK: ConnectPayload

    func testConnectPayloadRoundTrip() throws {
        let payload = ConnectPayload(provider: .codex, refreshToken: "ref-456", accountID: "acct-789")
        let decoded = ConnectPayload.decode(try payload.encoded())
        XCTAssertEqual(decoded, payload)
        XCTAssertEqual(decoded?.codexCredentials?.refreshToken, "ref-456")
        XCTAssertEqual(decoded?.codexCredentials?.accountID, "acct-789")
        XCTAssertNil(decoded?.claudeCredentials)
    }

    func testConnectPayloadRejectsForeignJSON() {
        XCTAssertNil(ConnectPayload.decode("{\"type\":\"other\",\"provider\":\"codex\",\"refreshToken\":\"x\"}"))
        XCTAssertNil(ConnectPayload.decode("not json"))
    }

    func testConnectPayloadClaude() {
        let payload = ConnectPayload(provider: .claude, refreshToken: "ref-456")
        XCTAssertEqual(payload.claudeCredentials?.refreshToken, "ref-456")
        XCTAssertNil(payload.codexCredentials)
    }
}
