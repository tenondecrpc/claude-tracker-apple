## MODIFIED Requirements

### Requirement: iOS reads UsageState from iCloud Drive
The iOS app SHALL watch the Tempo iCloud directory using `NSMetadataQuery` with `NSMetadataQueryUbiquitousDocumentsScope` (or resolved container Documents scope) and SHALL ingest both `usage.json` and `usage-history.json`. When `usage.json` changes, the app SHALL decode the JSON into a `UsageState` and relay it to the watch via `WatchConnectivity`. When `usage-history.json` changes, the app SHALL decode the history payload for iOS history/activity rendering.

#### Scenario: Usage file detected on iCloud
- **WHEN** `NSMetadataQuery` detects a new or updated `usage.json` in iCloud Drive
- **THEN** the iOS app reads the file via `NSFileCoordinator`, decodes `UsageState`, updates dashboard state, and sends it to the watch via `transferUserInfo`

#### Scenario: History file detected on iCloud
- **WHEN** `NSMetadataQuery` detects a new or updated `usage-history.json` in iCloud Drive
- **THEN** the iOS app reads the file via `NSFileCoordinator`, decodes history snapshots, and updates iOS activity/history view models

#### Scenario: File not yet downloaded
- **WHEN** `usage.json` or `usage-history.json` exists in iCloud but has not been downloaded to the device
- **THEN** the app calls `FileManager.startDownloadingUbiquitousItem(at:)` and waits for the next `NSMetadataQueryDidUpdate` notification

#### Scenario: iOS app becomes active
- **WHEN** the iOS app enters the foreground
- **THEN** `NSMetadataQuery` is restarted to pick up any iCloud changes that occurred while backgrounded

### Requirement: iOS does not require OAuth sign-in
The iOS app SHALL NOT require user OAuth sign-in and SHALL NOT use local OAuth/API polling as a data source for dashboard or history screens. Authentication remains owned by macOS, and iOS reads synced usage data from iCloud Drive.

#### Scenario: iOS app launches without credentials
- **WHEN** the iOS app launches and no OAuth tokens are in Keychain
- **THEN** the app shows iCloud-sync-driven UI states (waiting/syncing/stale) and does not present a sign-in flow

#### Scenario: Usage data arrives via iCloud
- **WHEN** `usage.json` appears in iCloud Drive
- **THEN** the iOS app transitions to connected state, renders usage UI, and relays data to the watch

### Requirement: Stale data indicator
The iOS app SHALL track the timestamp of the last successfully received iCloud data and expose stale indicators for usage and history freshness. Data older than 30 minutes SHALL be marked stale in the appropriate UI surface.

#### Scenario: Fresh data
- **WHEN** `usage.json` and required history data were updated less than 30 minutes ago
- **THEN** no staleness indicator is shown

#### Scenario: Usage stale data
- **WHEN** the latest `usage.json` snapshot is older than 30 minutes
- **THEN** the dashboard displays "Last updated Xm ago" and a stale warning state

#### Scenario: History stale while usage is fresh
- **WHEN** `usage.json` is fresh but `usage-history.json` is older than 30 minutes
- **THEN** the dashboard remains active and the activity screen shows a targeted stale-history indicator
