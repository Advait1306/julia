import Foundation
import LocalAuthentication
import Security

/// The macOS login keychain encrypts the secret and restricts access to this app
/// using its default code-signing ACL. Never put the key in defaults or a scheme.
nonisolated struct JevKeychain: Sendable {
    let service: String
    private let account = "jev-api-key"

    init(service: String = (Bundle.main.bundleIdentifier ?? "com.advait.julia") + ".jev") {
        self.service = service
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecAttrSynchronizable as String: false]
    }

    func read() throws -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        try check(status)
        guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw Failure.invalidData
        }
        return key
    }

    /// Check metadata without loading the secret or opening an authorization dialog.
    func containsKey() throws -> Bool {
        var request = query
        request[kSecReturnAttributes as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        request[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(request as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }

    func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: \.isWhitespace) else { throw Failure.invalidKey }
        let attributes: [String: Any] = [kSecValueData as String: Data(key.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query.merging(attributes) { _, new in new }
            item[kSecAttrLabel as String] = "Julia · Jev API key"
            // SecItemAdd's default ACL trusts only the creating application.
            try check(SecItemAdd(item as CFDictionary, nil))
        } else {
            try check(status)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw Failure.keychain(status) }
    }

    enum Failure: LocalizedError {
        case invalidKey, invalidData, keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidKey: "Enter an API key without spaces or line breaks."
            case .invalidData: "The stored key could not be read. Enter it again in Settings → AI."
            case .keychain(let status):
                "Keychain could not complete the operation (\(status)). Unlock your login keychain and try again."
            }
        }
    }
}
