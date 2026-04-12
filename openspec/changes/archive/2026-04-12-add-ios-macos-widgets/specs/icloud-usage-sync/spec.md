## ADDED Purpose

Ensure iOS widget data is derived from iCloud-synced usage and kept fresh without direct network work inside the widget extension.

## ADDED Requirements

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
