## MODIFIED Requirements

### Requirement: iOS reads per-account UsageState from iCloud Drive
The iOS app SHALL watch the Tempo iCloud directory tree using `NSMetadataQuery` with `NSMetadataQueryUbiquitousDocumentsScope`. It SHALL observe each `Tempo/accounts/<accountId>/usage.json` file and the index file `Tempo/accounts/index.json`. When a per-account file changes, the app SHALL decode the JSON into a `UsageState` (carrying `accountId`) and update its in-memory map of per-account states. The iOS reader SHALL NOT read the legacy flat `Tempo/usage.json` path under any condition.

#### Scenario: Per-account usage file detected on iCloud
- **WHEN** `NSMetadataQuery` detects a new or updated `Tempo/accounts/<A>/usage.json` in iCloud Drive
- **THEN** the iOS app reads the file via `NSFileCoordinator`, decodes the `UsageState`, and updates its map with that account's latest state

#### Scenario: Index file parsed to enumerate accounts
- **WHEN** `Tempo/accounts/index.json` is read
- **THEN** the iOS app uses it to populate the user-visible list of accounts and to decide which per-account files to observe

#### Scenario: File not yet downloaded
- **WHEN** an account's `usage.json` exists in iCloud but has not been downloaded to the device
- **THEN** the app calls `FileManager.startDownloadingUbiquitousItem(at:)` and waits for the next `NSMetadataQueryDidUpdate` notification

#### Scenario: Legacy flat path never observed
- **WHEN** the iOS reader starts
- **THEN** it does not create an `NSMetadataQuery` predicate for `Tempo/usage.json` and ignores that path if it happens to be present

#### Scenario: iOS app becomes active
- **WHEN** the iOS app enters the foreground
- **THEN** `NSMetadataQuery` is restarted to pick up any iCloud changes that occurred while backgrounded

### Requirement: iOS does not require OAuth sign-in
The iOS app SHALL NOT require the user to sign in via OAuth. Authentication is handled entirely by the macOS app. The iOS app reads usage data from iCloud Drive written by macOS.

#### Scenario: iOS app launches without any accounts
- **WHEN** the iOS app launches and no `Tempo/accounts/` directory exists in iCloud
- **THEN** the app shows a "Connect via Mac app" status screen and waits for the per-account tree to appear

#### Scenario: Usage data arrives via iCloud
- **WHEN** a `Tempo/accounts/<A>/usage.json` appears in iCloud Drive
- **THEN** the iOS app transitions to connected state showing the account label as "Syncing from Mac" and relays that account's data to the watch when it is the active account

### Requirement: Stale data indicator per account
The iOS app SHALL track the timestamp of the last received `UsageState` per accountId. If the active account's data is older than 30 minutes, the app SHALL display a "Last updated Xm ago" indicator for that account.

#### Scenario: Fresh data for active account
- **WHEN** the active account's `usage.json` was updated less than 30 minutes ago
- **THEN** no staleness indicator is shown

#### Scenario: Stale data for active account
- **WHEN** the active account's `usage.json` was last updated more than 30 minutes ago
- **THEN** the app displays "Last updated Xm ago" in the UI

### Requirement: iOS materializes per-account widget snapshots from iCloud usage data
When the iOS app decodes a valid `UsageState` for an accountId, it SHALL derive a widget snapshot tagged with that accountId and write it to shared App Group storage for the iOS widget extension. The "active account" widget surface SHALL use the snapshot for the currently active accountId; per-account widgets configured with an `AccountIntent` SHALL use the snapshot for their configured accountId.

#### Scenario: Widget snapshot written on usage update
- **WHEN** `iCloudUsageReader` decodes a new `UsageState` for account A
- **THEN** the iOS app writes a corresponding widget snapshot tagged with accountId A to its shared App Group storage

#### Scenario: Widget snapshot includes freshness metadata
- **WHEN** the iOS app writes a per-account widget snapshot
- **THEN** it records the timestamp of the successful iCloud-driven update so widgets can render freshness state

### Requirement: iOS reloads widget timelines after snapshot updates
After writing a new per-account widget snapshot, the iOS app SHALL request a reload of Tempo widget timelines.

#### Scenario: Widget timelines reloaded after write
- **WHEN** the iOS app finishes writing an updated per-account widget snapshot
- **THEN** it calls WidgetKit reload APIs for Tempo's iOS widget kinds

#### Scenario: Invalid usage decode does not overwrite last valid widget data for that account
- **WHEN** a per-account `usage.json` cannot be decoded into a valid `UsageState`
- **THEN** the iOS app preserves that account's last valid widget snapshot instead of replacing it with empty or partial data
