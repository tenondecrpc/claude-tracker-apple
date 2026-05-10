import Foundation
import Security

// MARK: - AccountRegistry
//
// `AccountRegistry` is the macOS source of truth for the set of known
// Anthropic accounts and the currently active one. It holds only non-secret
// metadata (`Account` values: accountId, email, displayName, createdAt) and
// never stores OAuth credentials. Credentials live in `CredentialStore`.
//
// Persistence is split:
// - `accounts` is JSON-encoded and stored in the macOS Keychain under the
//   shared service `com.tenondev.tempo.claude.oauth` with the reserved
//   `kSecAttrAccount = "__registry__"` slot. This keeps the account list in
//   the same secure store as the credentials it indexes, so a Keychain
//   restore is atomic.
// - `activeAccountId` is a user preference and lives in `UserDefaults` under
//   `"tempo.activeAccountId"`. It is a local selection and is NOT synced via
//   iCloud; the iOS companion maintains its own active selection.
//
// `CredentialStore` treats `"__registry__"` as reserved and refuses to
// read or write that slot, so `AccountRegistry` issues its own direct
// `SecItem*` calls via the fileprivate `AccountRegistryStorage` helper.
//
// The iCloud mirror writer (`Tempo/accounts/<id>/account.json`,
// `Tempo/accounts/index.json`) is a separate concern (task 2.3) and lives
// outside this type.
@Observable
@MainActor
final class AccountRegistry {

    // MARK: Stored state

    /// The known accounts, in user-facing order. Observers see updates after
    /// every mutation. Empty on first launch.
    var accounts: [Account] = []

    /// The currently active accountId, or `nil` if no account is selected.
    /// Kept in sync with the `accounts` list: any `setActive` call with an
    /// unknown id is a no-op (plus `assertionFailure` in debug), and
    /// `remove` clears this value if the removed account was active.
    var activeAccountId: String? = nil

    // MARK: Init

    /// Loads persisted state from the Keychain (`__registry__` slot) and
    /// `UserDefaults`. A stored `activeAccountId` that no longer matches any
    /// known account is cleared on startup to keep the two fields coherent.
    init() {
        self.accounts = AccountRegistryStorage.loadAccounts()

        let storedActiveId = UserDefaults.standard.string(forKey: Self.activeAccountIdDefaultsKey)
        if let id = storedActiveId, accounts.contains(where: { $0.accountId == id }) {
            self.activeAccountId = id
        } else {
            self.activeAccountId = nil
            if storedActiveId != nil {
                UserDefaults.standard.removeObject(forKey: Self.activeAccountIdDefaultsKey)
            }
        }
    }

    // MARK: Mutating API

    /// Registers an account or refreshes its metadata.
    ///
    /// - If no existing entry matches `account.accountId`, the account is
    ///   appended to the end of the list.
    /// - If an entry already exists, its `email`, `displayName`, and
    ///   `createdAt` fields are overwritten in place. The ordering of
    ///   `accounts` is preserved so UI lists do not reshuffle on a sign-in
    ///   refresh.
    ///
    /// `add` does NOT auto-activate the new account. The caller (typically
    /// the sign-in flow) decides when to call `setActive(accountId:)`.
    func add(_ account: Account) {
        if let index = accounts.firstIndex(where: { $0.accountId == account.accountId }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        persistAccounts()
    }

    /// Removes an account from the registry by `accountId`.
    ///
    /// - The matching entry (if any) is removed from `accounts`.
    /// - If the removed account was the active one, `activeAccountId` is
    ///   cleared. Re-assigning to a replacement account is the caller's
    ///   responsibility (see task 4.5).
    ///
    /// `remove` does NOT delete Keychain credentials or iCloud data for the
    /// account; that cleanup is task 2.5.
    func remove(accountId: String) {
        let countBefore = accounts.count
        accounts.removeAll { $0.accountId == accountId }
        let didRemoveAccount = accounts.count != countBefore

        if activeAccountId == accountId {
            activeAccountId = nil
            persistActiveAccountId()
        }

        if didRemoveAccount {
            persistAccounts()
        }
    }

    /// Updates the display name of a known account. No-op if the accountId
    /// is unknown. `email`, `accountId`, and `createdAt` are never changed
    /// by this call.
    func rename(accountId: String, displayName: String) {
        guard let index = accounts.firstIndex(where: { $0.accountId == accountId }) else {
            return
        }
        let existing = accounts[index]
        if existing.displayName == displayName { return }
        accounts[index] = Account(
            accountId: existing.accountId,
            email: existing.email,
            displayName: displayName,
            createdAt: existing.createdAt
        )
        persistAccounts()
    }

    /// Updates `activeAccountId`. Passing `nil` clears the active selection.
    /// Passing a non-nil id that is not present in `accounts` is a no-op and
    /// triggers `assertionFailure` in debug builds so callers can catch the
    /// misuse.
    func setActive(accountId: String?) {
        if let id = accountId {
            guard accounts.contains(where: { $0.accountId == id }) else {
                assertionFailure("AccountRegistry.setActive called with unknown accountId: \(id)")
                return
            }
            if activeAccountId == id { return }
            activeAccountId = id
        } else {
            if activeAccountId == nil { return }
            activeAccountId = nil
        }
        persistActiveAccountId()
    }

    // MARK: Persistence

    private static let activeAccountIdDefaultsKey = "tempo.activeAccountId"

    private func persistAccounts() {
        do {
            try AccountRegistryStorage.saveAccounts(accounts)
        } catch {
            assertionFailure("Failed to persist AccountRegistry to Keychain: \(error)")
        }
    }

    private func persistActiveAccountId() {
        if let id = activeAccountId {
            UserDefaults.standard.set(id, forKey: Self.activeAccountIdDefaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.activeAccountIdDefaultsKey)
        }
    }
}

// MARK: - AccountRegistryStorage
//
// Direct Keychain access for the reserved `__registry__` slot. This bypasses
// `CredentialStore` because `CredentialStore`'s public API rejects the
// reserved account name. The slot shares the service used by per-account
// credential slots so that registry and credentials live together.

fileprivate enum AccountRegistryStorage {

    private static let service = "com.tenondev.tempo.claude.oauth"
    private static let reservedAccount = "__registry__"

    /// Load the persisted `[Account]` payload, or an empty array if the slot
    /// is absent or cannot be decoded.
    static func loadAccounts() -> [Account] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reservedAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([Account].self, from: data)) ?? []
    }

    /// Encode and store the given `[Account]` payload. Creates or updates
    /// the Keychain item as needed. Throws on a non-recoverable Keychain
    /// failure.
    static func saveAccounts(_ accounts: [Account]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(accounts)

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reservedAccount
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
            throw AccountRegistryStorageError.keychainSaveFailed(status: addStatus)
        }
    }
}

// MARK: - AccountRegistryStorageError

fileprivate enum AccountRegistryStorageError: LocalizedError {
    case keychainSaveFailed(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainSaveFailed(let status):
            return "Failed to save AccountRegistry to Keychain (status: \(status))."
        }
    }
}
