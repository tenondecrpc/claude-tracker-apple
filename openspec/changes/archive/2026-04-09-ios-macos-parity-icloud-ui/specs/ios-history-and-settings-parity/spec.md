## ADDED Requirements

### Requirement: iOS activity screen renders history from iCloud snapshots
The iOS app SHALL render a usage activity/history experience using `usage-history.json` mirrored in iCloud, including time-series trends for 5-hour and 7-day utilization.

#### Scenario: History data available
- **WHEN** iCloud provides a valid `usage-history.json` with at least one snapshot
- **THEN** the activity screen displays a chart/list based on those snapshots

#### Scenario: History data absent
- **WHEN** no history file is available in iCloud yet
- **THEN** the activity screen displays an empty-state message explaining that history will appear after Mac sync

### Requirement: Activity screen supports analysis controls for usability
The activity screen SHALL provide user controls that improve interpretation of historical data (date range and series visibility) while preserving readability on iPhone layouts.

#### Scenario: User changes date range
- **WHEN** the user selects a different history range (for example 24h, 7d, or 30d)
- **THEN** the chart updates to the selected time window without leaving the screen

#### Scenario: User toggles visible series
- **WHEN** the user disables one of the utilization series
- **THEN** only the selected metrics remain visible and the legend reflects the change

### Requirement: iOS settings screen provides parity-relevant controls and diagnostics
The iOS app SHALL include a settings screen that mirrors macOS intent for user control where meaningful on iOS, including display preferences, iCloud sync health, and data freshness diagnostics.

#### Scenario: Display preference persists
- **WHEN** the user changes an iOS display preference (for example 24-hour time formatting)
- **THEN** the chosen value persists across app relaunches

#### Scenario: Sync diagnostics visible
- **WHEN** the settings screen is opened
- **THEN** it shows current iCloud sync status and last successful update timestamps for usage/history payloads

### Requirement: iOS history and settings use Claude palette styling
The iOS activity and settings screens SHALL use `ClaudeCodeTheme` tokens for all major UI surfaces and semantic colors.

#### Scenario: Activity chart styling
- **WHEN** chart lines, labels, and containers are rendered
- **THEN** their colors map to `ClaudeCodeTheme` accent/status/text tokens

#### Scenario: Settings card styling
- **WHEN** settings rows and grouped sections are rendered
- **THEN** backgrounds, dividers, and text use Claude token colors instead of default system gray palettes
