## MODIFIED Requirements

### Requirement: TransferUserInfo payload includes usage history
The iOS companion SHALL include an `usageHistory` key in the `transferUserInfo` dictionary containing the last 7 days of `UsageHistorySnapshot` entries encoded as JSON `Data`. The `WatchSessionReceiver` SHALL decode this key and store the snapshots in `TokenStore.usageHistory`.

#### Scenario: History included in payload
- **WHEN** the iOS companion sends a `transferUserInfo` with `type: "UsageState"`
- **THEN** the dictionary includes an `usageHistory` key containing a `Data` blob of JSON-encoded `[UsageHistorySnapshot]`

#### Scenario: Watch receives and decodes history
- **WHEN** `WatchSessionReceiver` processes a `userInfo` dictionary containing an `usageHistory` Data value
- **THEN** it decodes the data to `[UsageHistorySnapshot]` and calls `store.applyHistory(snapshots)`

#### Scenario: History key missing (backward compatibility)
- **WHEN** the `userInfo` dictionary does not contain an `usageHistory` key
- **THEN** `WatchSessionReceiver` does not modify `store.usageHistory` (retains previous value or empty array)

#### Scenario: History decode failure
- **WHEN** the `usageHistory` data cannot be decoded
- **THEN** `WatchSessionReceiver` logs the error and does not crash; existing history is retained

## ADDED Requirements

### Requirement: TokenStore stores usage history
`TokenStore` SHALL expose a `usageHistory: [UsageHistorySnapshot]` property (initially empty). An `applyHistory(_ snapshots: [UsageHistorySnapshot])` method SHALL replace the stored history with the provided snapshots.

#### Scenario: History applied
- **WHEN** `applyHistory` is called with 7 snapshots
- **THEN** `store.usageHistory` contains exactly those 7 snapshots

#### Scenario: History replaced on update
- **WHEN** `applyHistory` is called with new snapshots while old snapshots exist
- **THEN** `store.usageHistory` contains only the new snapshots

### Requirement: TokenStore tracks last session
`TokenStore` SHALL expose a computed `lastSession: SessionInfo?` property returning the most recent entry from `sessions` sorted by `timestamp`.

#### Scenario: Sessions available
- **WHEN** `store.sessions` contains 3 entries
- **THEN** `store.lastSession` returns the entry with the latest `timestamp`

#### Scenario: No sessions
- **WHEN** `store.sessions` is empty
- **THEN** `store.lastSession` is nil
