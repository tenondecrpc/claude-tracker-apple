## ADDED Requirements

### Requirement: Account model
Tempo SHALL define an `Account` type in `Shared/` as a `Codable`, `Identifiable`, `Equatable` value type with the following fields:
- `accountId: String` - canonical, immutable identifier for the account
- `email: String?` - the OAuth account email, present for OAuth accounts and nil for synthetic CLI-only accounts
- `displayName: String?` - optional user-facing label, defaults to the email or the synthetic id when nil
- `createdAt: Date` - the timestamp when the account was added to the registry

`id` SHALL return `accountId`. `accountId` SHALL be the single source of truth for equality; two `Account` values with the same `accountId` SHALL be considered equal.

#### Scenario: OAuth account created from email
- **WHEN** an `Account` is created for an OAuth sign-in whose profile email is `" User@Example.COM "`
- **THEN** `accountId` is `"user@example.com"`, `email` is `"user@example.com"`, `displayName` is `nil`, and `createdAt` is set to the current time

#### Scenario: Synthetic CLI-only account
- **WHEN** an `Account` is created from a CLI-only profile that did not report an email
- **THEN** `accountId` starts with the prefix `cli-local-`, `email` is `nil`, and `displayName` defaults to a user-visible placeholder

### Requirement: accountId canonicalization
The system SHALL canonicalize incoming email strings to produce a stable `accountId`:
- Unicode-normalize via NFC
- Trim surrounding whitespace
- Lowercase ASCII letters
- Reject empty strings (caller SHALL fall back to a synthetic `cli-local-<shortHash>` id)

The canonicalized form SHALL be reused verbatim for Keychain `kSecAttrAccount` values and for the iCloud directory name. File system escaping SHALL only affect characters outside `[a-z0-9._@-]`, which SHALL be percent-encoded in the directory name while the in-memory `accountId` remains the canonical form.

#### Scenario: Mixed-case email normalized
- **WHEN** canonicalizing `"Alex.Jones@Anthropic.com"`
- **THEN** the result is `"alex.jones@anthropic.com"`

#### Scenario: Empty email rejected
- **WHEN** canonicalizing an empty string
- **THEN** the caller receives `nil` and SHALL generate a synthetic id instead

#### Scenario: Unsafe filesystem characters encoded in path only
- **WHEN** an accountId contains a character outside `[a-z0-9._@-]`
- **THEN** the in-memory `accountId` still holds the canonical form and the iCloud directory name uses percent-encoding for that character

### Requirement: AccountRegistry on macOS
The macOS app SHALL provide an `AccountRegistry` type (declared `@Observable @MainActor final class` in `Tempo macOS/`) that:
- Holds `accounts: [Account]` as the ordered list of known accounts
- Holds `activeAccountId: String?` as the macOS-local active account selection
- Exposes `add(_:)`, `remove(_:)`, `rename(accountId:displayName:)`, and `setActive(_:)` mutation methods
- Persists `accounts` to the macOS Keychain under service `com.tenondev.tempo.claude.oauth`, account `__registry__`, using `kSecAttrAccessibleAfterFirstUnlock`
- Persists `activeAccountId` to `UserDefaults` under key `com.tenondev.tempo.activeAccountId`
- Publishes change notifications through `@Observable` so SwiftUI surfaces react to account list and active-account updates

Credentials SHALL NEVER be stored inside the registry; the registry only stores non-secret metadata (accountId, email, displayName, createdAt).

#### Scenario: Adding an account persists to Keychain
- **WHEN** `AccountRegistry.add(_:)` is called with a new `Account`
- **THEN** the in-memory `accounts` array contains the new account, the `__registry__` Keychain item is updated with the serialized list, and observers are notified

#### Scenario: Removing an account clears related state
- **WHEN** `AccountRegistry.remove(_:)` is called with an existing accountId
- **THEN** the account is removed from the list, the registry Keychain item is rewritten, the account's Keychain credential slot is deleted, the iCloud directory `Tempo/accounts/<accountId>/` is deleted, and if the removed id equals `activeAccountId` the registry SHALL set `activeAccountId` to the first remaining account or `nil` when none remain

#### Scenario: Renaming preserves identity
- **WHEN** `AccountRegistry.rename(accountId:displayName:)` is called
- **THEN** only the `displayName` of that account changes; `accountId`, `email`, and `createdAt` are unchanged

#### Scenario: Registry Keychain item is read-only to non-Tempo callers
- **WHEN** the `__registry__` Keychain item is written
- **THEN** it is created with `kSecClassGenericPassword`, service `com.tenondev.tempo.claude.oauth`, account `__registry__`, and `kSecAttrAccessibleAfterFirstUnlock`

### Requirement: Registry mirrors public metadata to iCloud
The macOS `AccountRegistry` SHALL mirror non-secret account metadata to iCloud so iOS can discover accounts. For each account it SHALL write `Tempo/accounts/<accountId>/account.json` containing `{accountId, email, displayName, createdAt}` and maintain `Tempo/accounts/index.json` listing the accountIds in user-visible order. The registry SHALL NEVER write tokens, refresh tokens, or any field outside the published metadata.

#### Scenario: Mirror write after add
- **WHEN** an account is added to the registry
- **THEN** the corresponding `account.json` is written to iCloud and `accounts/index.json` is updated to include the new accountId

#### Scenario: Mirror write after remove
- **WHEN** an account is removed from the registry
- **THEN** `accounts/index.json` is updated to exclude that accountId and the account's iCloud directory is deleted

#### Scenario: No secret leakage
- **WHEN** `account.json` is serialized
- **THEN** it contains only `accountId`, `email`, `displayName`, and `createdAt` fields and no token, refresh-token, or keychain-related fields
