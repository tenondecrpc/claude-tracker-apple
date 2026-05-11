# watch-refresh-ui Specification

## Purpose
TBD - created by archiving change watch-on-demand-relay-refresh. Update Purpose after archive.
## Requirements
### Requirement: Dashboard shows a refresh button in a bottom footer
The watch dashboard SHALL display a refresh icon button (`arrow.clockwise`) centered in a footer row below the usage ring. The button SHALL be visible in all dashboard states but disabled when `activeAccountId` is nil or `hasNoActiveAccount` is true.

#### Scenario: Button visible with active account
- **WHEN** the dashboard renders with a known `activeAccountId`
- **THEN** the refresh button is visible and enabled

#### Scenario: Button disabled without active account
- **WHEN** the dashboard renders with `hasNoActiveAccount` true
- **THEN** the refresh button is visible but disabled (dimmed)

### Requirement: Refresh button renders three visual states
The button SHALL render: idle (static `arrow.clockwise`), in-progress (rotating symbol effect), error (icon with red dot badge). Transitions happen on the main actor.

#### Scenario: Idle state
- **WHEN** the coordinator state is `.idle`
- **THEN** the button shows a static `arrow.clockwise` icon

#### Scenario: In-progress state
- **WHEN** the coordinator state is `.inProgress`
- **THEN** the button shows a rotating `arrow.clockwise` icon

#### Scenario: Error state
- **WHEN** the coordinator state is `.error`
- **THEN** the button shows `arrow.clockwise` with a small red dot overlay

### Requirement: Tapping error state shows alert then retries
Tapping the refresh button while in `.error` state SHALL present a short alert with the error reason, then issue a new refresh attempt.

#### Scenario: Error tap shows reason and retries
- **WHEN** the user taps the button while in `.error` state
- **THEN** an alert shows the error reason and a new `RequestFreshRelay` is sent after dismissal

### Requirement: Dashboard shows freshness indicator
The dashboard SHALL display a compact "Updated Xm ago" label inside the ring center, below the metric labels. The timestamp is driven by `TokenStore.lastRelayReceivedAt` for the active account.

#### Scenario: Fresh data
- **WHEN** the last relay was received less than 60 seconds ago
- **THEN** the label shows "Updated just now"

#### Scenario: Stale data
- **WHEN** the last relay was received 5 minutes ago
- **THEN** the label shows "Updated 5m ago"

#### Scenario: No data ever received
- **WHEN** no `UsageState` has been applied for the active account
- **THEN** no freshness label is shown

### Requirement: Accessibility for refresh control
The refresh button SHALL have `.accessibilityLabel("Refresh usage")` and `.accessibilityValue` reflecting the current state (idle/refreshing/error reason).

#### Scenario: VoiceOver announces state
- **WHEN** VoiceOver focuses the refresh button
- **THEN** it announces "Refresh usage" and the current state value

