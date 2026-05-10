## MODIFIED Requirements

### Requirement: Receiver routes account-aware UsageState payloads to TokenStore
`WatchSessionReceiver` SHALL implement `session(_:didReceiveApplicationContext:)`. When the payload contains `"type": "UsageState"` it SHALL decode a `UsageState`, extract the `accountId` and `accountLabel` fields, and call `store.apply(_:forAccountId:label:)` on the `@MainActor`. When the payload contains `"type": "NoActiveAccount"` it SHALL call `store.clearActiveAccount()` on the `@MainActor`.

`WatchSessionReceiver` SHALL also continue to implement `session(_:didReceiveUserInfo:)` for `SessionInfo` payloads. It SHALL call `store.applySession(_:forAccountId:)` on the `@MainActor` and SHALL ignore the payload when its `accountId` does not match the current active account.

#### Scenario: Valid active-account UsageState payload received
- **WHEN** `didReceiveApplicationContext` fires with `["type": "UsageState", "accountId": "A", "accountLabel": "a@example.com", ...]`
- **THEN** `TokenStore.apply(_:forAccountId:label:)` is called with the decoded `UsageState`, accountId `"A"`, and label `"a@example.com"`

#### Scenario: NoActiveAccount payload received
- **WHEN** `didReceiveApplicationContext` fires with `["type": "NoActiveAccount"]`
- **THEN** `TokenStore.clearActiveAccount()` is called and any displayed usage state is cleared

#### Scenario: SessionInfo for non-active account is ignored
- **WHEN** `didReceiveUserInfo` fires with `SessionInfo` whose `accountId` does not match the current active accountId
- **THEN** the payload is silently ignored and `TokenStore` is not modified

#### Scenario: Unknown type payload ignored
- **WHEN** either delivery fires with a `"type"` the receiver does not recognize
- **THEN** the payload is silently ignored and `TokenStore` is not modified

#### Scenario: Missing type key ignored
- **WHEN** a payload arrives without a `"type"` key
- **THEN** the payload is silently ignored and `TokenStore` is not modified

### Requirement: Main actor dispatch for store mutation
`WatchSessionReceiver` SHALL dispatch all `TokenStore` mutation calls (including `apply`, `clearActiveAccount`, and `applySession`) to `@MainActor` using `Task { @MainActor in ... }` since `WCSessionDelegate` methods are called on a background thread.

#### Scenario: Background thread delivery
- **WHEN** `didReceiveApplicationContext` or `didReceiveUserInfo` is invoked on a background thread
- **THEN** all `TokenStore` mutations execute on the main actor without data races
