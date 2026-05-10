## MODIFIED Requirements

### Requirement: WCSession activated at iOS app launch
`WatchRelayManager` SHALL activate `WCSession.default` at iOS app launch by setting itself as delegate and calling `activate()`. The delegate MUST be set before `activate()` is called.

#### Scenario: Session activated on launch
- **WHEN** the iOS app finishes launching
- **THEN** `WCSession.default.delegate` is set and `activate()` is called before any transfer is attempted

### Requirement: Active-account UsageState delivered via updateApplicationContext
`WatchRelayManager` SHALL send the iPhone's currently active account `UsageState` to the watch using `WCSession.default.updateApplicationContext(_:)` so the watch always has the latest snapshot. The payload SHALL contain `"type": "UsageState"` plus `"accountId": <current active id>` and `"accountLabel": <display label>`. The payload SHALL encode all `UsageState` fields as primitive values (`Double`, `TimeInterval`, `Bool`).

If no account is active on iPhone, `WatchRelayManager` SHALL send a context update with `"type": "NoActiveAccount"` so the watch can clear its display state.

#### Scenario: Active account context sent after iCloud update
- **WHEN** iOS decodes a new `UsageState` for the currently active accountId
- **THEN** `WatchRelayManager` calls `updateApplicationContext` with the encoded payload including `accountId` and `accountLabel`

#### Scenario: Active account change triggers immediate context update
- **WHEN** the user changes the iOS active accountId
- **THEN** `WatchRelayManager` immediately calls `updateApplicationContext` with the newly active account's latest known `UsageState`

#### Scenario: No active account sends sentinel
- **WHEN** the iPhone has no active account (registry empty or user signed all out)
- **THEN** `WatchRelayManager` calls `updateApplicationContext` with `"type": "NoActiveAccount"` and no `UsageState` fields

### Requirement: Account-tagged SessionInfo delivered via transferUserInfo
`WatchRelayManager` SHALL send `SessionInfo` completion events to the watch using `WCSession.default.transferUserInfo(_:)` with `"type": "SessionInfo"` and a required `"accountId"` field. The watch SHALL only surface the completion alert if the received `accountId` matches its currently known active accountId; other events are dropped.

#### Scenario: Session completion for active account
- **WHEN** iOS receives a completion event for the currently active accountId
- **THEN** `WatchRelayManager` sends a `transferUserInfo` payload with `"type": "SessionInfo"`, the session fields, and `"accountId"` equal to that accountId

#### Scenario: Session completion for non-active account
- **WHEN** iOS receives a completion event for an accountId that is not currently active on iPhone
- **THEN** `WatchRelayManager` does NOT send a completion alert to the watch and the event is recorded only for iOS activity

### Requirement: Stale UsageState transfers are not a concern with applicationContext
Because active-account `UsageState` is delivered via `updateApplicationContext`, each new delivery replaces the previous one. `WatchRelayManager` SHALL NOT enqueue `UsageState` payloads via `transferUserInfo` for active-account snapshots. Completion events via `transferUserInfo` SHALL NOT be cancelled when the iOS active account changes.

#### Scenario: Switching active account does not cancel pending completions
- **WHEN** a pending `SessionInfo` `transferUserInfo` exists for account A and the user switches active to account B on iPhone
- **THEN** the pending transfer still completes and is not cancelled

#### Scenario: UsageState payloads never use transferUserInfo
- **WHEN** iOS produces a new active-account `UsageState`
- **THEN** it is sent via `updateApplicationContext` and no `UsageState` transfer is queued via `transferUserInfo`
