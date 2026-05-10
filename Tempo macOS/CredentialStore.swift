import Foundation
import Security

// MARK: - StoredCredentials

struct StoredCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]
}

// MARK: - CredentialStore
//
// Keychain-backed storage for Anthropic OAuth credentials, keyed by the
// canonical accountId (lowercased email or synthetic CLI id).
//
// Contract:
// - All items live under `kSecAttrService = "com.tenondev.tempo.claude.oauth"`.
// - `kSecAttrAccount` is the canonical accountId for a real account.
// - The account string `"__registry__"` is reserved for the non-secret
//   `AccountRegistry` payload written in task 2.2; `CredentialStore` never
//   reads or writes that slot and `knownAccountIds()` filters it out.
// - There is no longer a fixed single-account slot. Callers must pass an
//   accountId to every operation. Migration and cleanup of any legacy
//   layout are handled outside this type (see task 2.4).

enum CredentialStore {

    private static let service = "com.tenondev.tempo.claude.oauth"

    /// Reserved `kSecAttrAccount` value owned by `AccountRegistry` (task 2.2).
    /// `CredentialStore` never reads or writes this slot; it is only listed
    /// here so `knownAccountIds()` can filter it out of enumeration results.
    private static let reservedRegistryAccount = "__registry__"

    // MARK: Public API

    /// Saves OAuth credentials for the given accountId, creating or updating
    /// the Keychain item under the shared service.
    static func save(_ credentials: StoredCredentials, for accountId: String) throws {
        try validate(accountId)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(credentials)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId
        ]

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        if updateStatus == errSecSuccess { return }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            throw CredentialStoreError.keychainSaveFailed(status: addStatus)
        }
    }

    /// Loads OAuth credentials for the given accountId, or `nil` if the
    /// Keychain has no matching item or decoding fails.
    static func load(for accountId: String) -> StoredCredentials? {
        guard (try? validate(accountId)) != nil else { return nil }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StoredCredentials.self, from: data)
    }

    /// Deletes the credential slot for the given accountId. A missing item
    /// is not an error. Any other failure is surfaced.
    static func delete(for accountId: String) throws {
        try validate(accountId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId
        ]
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw CredentialStoreError.keychainDeleteFailed(status: status)
        }
    }

    /// Enumerates every `kSecAttrAccount` value stored under the shared
    /// service, excluding the reserved `__registry__` slot owned by
    /// `AccountRegistry` (task 2.2). Returns an empty array if no items are
    /// stored or the query fails in a benign way.
    static func knownAccountIds() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { return [] }

        let items: [[String: Any]]
        if let array = result as? [[String: Any]] {
            items = array
        } else if let single = result as? [String: Any] {
            items = [single]
        } else {
            return []
        }

        return items.compactMap { item in
            item[kSecAttrAccount as String] as? String
        }.filter { $0 != reservedRegistryAccount }
    }

    /// Returns true if the credentials have a non-expired access token
    /// (with a 60s buffer).
    static func isValid(_ credentials: StoredCredentials) -> Bool {
        credentials.expiresAt > Date().addingTimeInterval(60)
    }

    // MARK: - Private

    private static func validate(_ accountId: String) throws {
        let trimmed = accountId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            throw CredentialStoreError.invalidAccountId
        }
        if accountId == reservedRegistryAccount {
            throw CredentialStoreError.reservedAccountId
        }
    }
}

// MARK: - CredentialStoreError

enum CredentialStoreError: LocalizedError {
    case keychainSaveFailed(status: OSStatus)
    case keychainDeleteFailed(status: OSStatus)
    case invalidAccountId
    case reservedAccountId

    var errorDescription: String? {
        switch self {
        case .keychainSaveFailed(let status):
            return "Failed to save credentials to Keychain (status: \(status))."
        case .keychainDeleteFailed(let status):
            return "Failed to delete credentials from Keychain (status: \(status))."
        case .invalidAccountId:
            return "Account id must be a non-empty string."
        case .reservedAccountId:
            return "Account id \"__registry__\" is reserved for AccountRegistry."
        }
    }
}
