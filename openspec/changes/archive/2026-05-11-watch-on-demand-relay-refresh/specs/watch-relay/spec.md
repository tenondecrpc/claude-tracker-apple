## ADDED Requirements

### Requirement: WatchRelayManager handles RequestFreshRelay messages from watch
`WatchRelayManager` SHALL implement `session(_:didReceiveMessage:replyHandler:)` to handle incoming `sendMessage` calls from the watch. When the message payload contains `["type": "RequestFreshRelay"]`, the relay SHALL invoke a callback (`onFreshRelayRequested`) and reply with `["ok": true]`. Unknown message types SHALL be ignored with a reply of `["ok": false, "reason": "unknown type"]`.

#### Scenario: Valid RequestFreshRelay received
- **WHEN** the iPhone receives a `sendMessage` with `["type": "RequestFreshRelay"]`
- **THEN** `onFreshRelayRequested` is called and the reply handler sends `["ok": true]`

#### Scenario: Unknown message type received
- **WHEN** the iPhone receives a `sendMessage` with an unrecognized type
- **THEN** the reply handler sends `["ok": false, "reason": "unknown type"]` and no callback fires

#### Scenario: Message without type key
- **WHEN** the iPhone receives a `sendMessage` without a `"type"` key
- **THEN** the reply handler sends `["ok": false, "reason": "missing type"]`

### Requirement: AppCoordinator wires fresh relay request to iCloud restart and re-send
When `WatchRelayManager.onFreshRelayRequested` fires, `AppCoordinator` SHALL call `iCloudUsageReader.restart()` to pick up any iCloud changes, then re-send the active account's `UsageState` via `relay.send(_:)` with current history, preferences, and appearance mode.

#### Scenario: Fresh relay requested with active account
- **WHEN** `onFreshRelayRequested` fires and the iOS app has a resolved active account with cached usage
- **THEN** `iCloudUsageReader.restart()` is called and the active account's `UsageState` is re-relayed to the watch

#### Scenario: Fresh relay requested without active account
- **WHEN** `onFreshRelayRequested` fires but no active account is resolved
- **THEN** `relay.sendNoActiveAccount()` is called so the watch clears stale state
