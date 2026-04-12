## Purpose

Define how the iOS app consumes usage data from iCloud and materializes it for downstream surfaces like watch sync and widgets.

## Requirements

### Requirement: iOS reads UsageState from iCloud Drive
The iOS app SHALL watch `~/Library/Mobile Documents/com~apple~CloudDocs/Tempo/usage.json` using `NSMetadataQuery` with `NSMetadataQueryUbiquitousDocumentsScope`. When the file changes, the app SHALL decode the JSON into a `UsageState` and relay it to the watch via `WatchConnectivity`.

#### Scenario: Usage file detected on iCloud
- **WHEN** `NSMetadataQuery` detects a new or updated `usage.json` in iCloud Drive
- **THEN** the iOS app reads the file via `NSFileCoordinator`, decodes `UsageState`, and sends it to the watch via `transferUserInfo`

#### Scenario: File not yet downloaded
- **WHEN** `usage.json` exists in iCloud but has not been downloaded to the device
- **THEN** the app calls `FileManager.startDownloadingUbiquitousItem(at:)` and waits for the next `NSMetadataQueryDidUpdate` notification

#### Scenario: iOS app becomes active
- **WHEN** the iOS app enters the foreground
- **THEN** `NSMetadataQuery` is restarted to pick up any iCloud changes that occurred while backgrounded

### Requirement: iOS does not require OAuth sign-in
The iOS app SHALL NOT require the user to sign in via OAuth. Authentication is handled entirely by the macOS app. The iOS app reads usage data from iCloud Drive written by macOS.

#### Scenario: iOS app launches without credentials
- **WHEN** the iOS app launches and no OAuth tokens are in Keychain
- **THEN** the app shows a "Connect via Mac app" status screen (not a sign-in screen) and watches iCloud for `usage.json`

#### Scenario: Usage data arrives via iCloud
- **WHEN** `usage.json` appears in iCloud Drive
- **THEN** the iOS app transitions to connected state showing "Syncing from Mac" and relays data to the watch

### Requirement: Stale data indicator
The iOS app SHALL track the timestamp of the last received `UsageState`. If the data is older than 30 minutes, the app SHALL display a "Last updated Xm ago" indicator.

#### Scenario: Fresh data
- **WHEN** `usage.json` was updated less than 30 minutes ago
- **THEN** no staleness indicator is shown

#### Scenario: Stale data
- **WHEN** `usage.json` was last updated more than 30 minutes ago
- **THEN** the app displays "Last updated Xm ago" in the UI

### Requirement: iOS materializes widget snapshot from iCloud usage data
When the iOS app decodes a valid `UsageState` from iCloud, it SHALL derive a widget snapshot and write it to shared App Group storage for the iOS widget extension.

#### Scenario: Widget snapshot written on usage update
- **WHEN** `iCloudUsageReader` decodes a new `UsageState` from `usage.json`
- **THEN** the iOS app writes a corresponding widget snapshot to its shared App Group storage

#### Scenario: Widget snapshot includes freshness metadata
- **WHEN** the iOS app writes the widget snapshot
- **THEN** it records the timestamp of the successful iCloud-driven update so widgets can render freshness state

### Requirement: iOS reloads widget timelines after snapshot updates
After writing a new widget snapshot, the iOS app SHALL request a reload of Tempo widget timelines.

#### Scenario: Widget timelines reloaded after write
- **WHEN** the iOS app finishes writing an updated widget snapshot
- **THEN** it calls WidgetKit reload APIs for Tempo's iOS widget kinds

#### Scenario: Invalid usage decode does not overwrite last valid widget data
- **WHEN** `usage.json` cannot be decoded into a valid `UsageState`
- **THEN** the iOS app preserves the last valid widget snapshot instead of replacing it with empty or partial data
