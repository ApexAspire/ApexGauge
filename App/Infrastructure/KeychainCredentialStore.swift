import ApexGaugeCore
import Foundation
import Security

actor KeychainCredentialStore: CredentialStore {
    private let service = "com.apex.apexgauge"

    func loadClaude() async throws -> ClaudeCredentials? {
        try load(ClaudeCredentials.self, account: "claude")
    }

    func saveClaude(_ credentials: ClaudeCredentials) async throws {
        try save(credentials, account: "claude")
    }

    func loadCodex() async throws -> CodexCredentials? {
        try load(CodexCredentials.self, account: "codex")
    }

    func saveCodex(_ credentials: CodexCredentials) async throws {
        try save(credentials, account: "codex")
    }

    func loadKimi() async throws -> KimiCredentials? {
        try load(KimiCredentials.self, account: "kimi")
    }

    func saveKimi(_ credentials: KimiCredentials) async throws {
        try save(credentials, account: "kimi")
    }

    func clear(provider: ProviderSnapshot.Provider) async throws {
        let status = SecItemDelete(baseQuery(account: provider.rawValue) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(status)
        }
    }

    private func load<Value: Decodable>(_ type: Value.Type, account: String) throws -> Value? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw keychainError(status)
        }
        guard let data = item as? Data else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.coderReadCorrupt.rawValue,
                userInfo: [NSLocalizedDescriptionKey: "Keychain returned an invalid credential payload."]
            )
        }
        return try JSONDecoder().decode(type, from: data)
    }

    private func save<Value: Encodable>(_ value: Value, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = baseQuery(account: account)
        let update = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw keychainError(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw keychainError(addStatus)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func keychainError(_ status: OSStatus) -> NSError {
        let message: String
        if let description = SecCopyErrorMessageString(status, nil) {
            message = description as String
        } else {
            message = "Keychain operation failed with status \(status)."
        }
        return NSError(
            domain: NSOSStatusErrorDomain,
            code: Int(status),
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
