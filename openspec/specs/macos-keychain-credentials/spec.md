## MODIFIED Requirements

### Requirement: macOS OAuth credentials stored per account in Keychain
The macOS `CredentialStore` SHALL store OAuth credentials in the macOS Keychain keyed by `accountId`. The Keychain service `com.tenondev.tempo.claude.oauth` SHALL be reused, with `kSecAttrAccount` set to the canonical `accountId` (lowercased email or synthetic `cli-local-*` id). Each account SHALL have exactly one credential item. There SHALL be no single shared `credentials` slot.

The iOS side already stores OAuth tokens in Keychain correctly via `AnthropicAPIClient.swift`; this change is scoped to macOS and does not modify the iOS `KeychainStore`.

#### Scenario: Keychain is the primary store per account
- **WHEN** `CredentialStore.save(_:for: accountId)` is called with an accountId and credentials
- **THEN** credentials are written to Keychain with `kSecClassGenericPassword`, `kSecAttrService: "com.tenondev.tempo.claude.oauth"`, `kSecAttrAccount: <accountId>`, and `kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock`

#### Scenario: Load reads per-account credentials
- **WHEN** `CredentialStore.load(for: accountId)` is called
- **THEN** it queries Keychain with `kSecAttrService: "com.tenondev.tempo.claude.oauth"` and `kSecAttrAccount: <accountId>` and decodes the stored `StoredCredentials`

#### Scenario: Delete removes only the targeted account
- **WHEN** `CredentialStore.delete(for: accountId)` is called
- **THEN** only the Keychain item for that accountId is removed and other accounts' credentials remain intact

#### Scenario: List returns all known account credentials
- **WHEN** `CredentialStore.knownAccountIds()` is called
- **THEN** it returns every `kSecAttrAccount` value associated with service `com.tenondev.tempo.claude.oauth`, excluding the reserved `__registry__` slot and any residual `credentials` slot left by dev builds

#### Scenario: Legacy fixed-slot is removed at startup
- **WHEN** the macOS app starts and a Keychain item with `kSecAttrAccount == "credentials"` exists under service `com.tenondev.tempo.claude.oauth`
- **THEN** Tempo deletes that item once on startup without attempting to migrate its contents

#### Scenario: Legacy credential file is removed at startup
- **WHEN** the macOS app starts and `~/.config/tempo-for-claude/credentials.json` exists on disk
- **THEN** Tempo deletes the file once on startup without reading its contents

#### Scenario: Registry item is not treated as credentials
- **WHEN** any credential query iterates Keychain accounts for the service
- **THEN** the reserved slot `__registry__` is excluded from results

#### Scenario: No regression for iOS
- **WHEN** the macOS Keychain multi-account scheme is implemented
- **THEN** the iOS `KeychainStore` in `Tempo/AnthropicAPIClient.swift` is unchanged
