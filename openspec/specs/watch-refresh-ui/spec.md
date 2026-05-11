# watch-refresh-ui Specification

## Purpose
TBD - created by archiving change watch-on-demand-relay-refresh. Update Purpose after archive.
## Requirements
### Requirement: Dashboard shows a refresh button in the compact footer
The watch dashboard SHALL display a refresh icon button (`arrow.clockwise`) on the right side of a compact footer row below the usage ring. The left side of the footer shows the freshness timestamp. The button SHALL be visible in all dashboard states but disabled when `activeAccountId` is nil or `hasNoActiveAccount` is true.

#### Scenario: Button visible with active account
- **WHEN** the dashboard renders with a known `activeAccountId`
- **THEN** the refresh button is visible and enabled on the right side of the footer

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

### Requirement: Freshness indicator uses compact format in footer
The dashboard SHALL display a compact relative time label on the left side of the footer row, preceded by a small clock icon. Format: "now" (< 60s), "Xm" (minutes), "Xh" (hours). The timestamp is driven by `TokenStore.lastRelayReceivedAtForActiveAccount`.

#### Scenario: Fresh data
- **WHEN** the last relay was received less than 60 seconds ago
- **THEN** the footer label shows clock icon + "now"

#### Scenario: Stale data
- **WHEN** the last relay was received 5 minutes ago
- **THEN** the footer label shows clock icon + "5m"

#### Scenario: No data ever received
- **WHEN** no `UsageState` has been applied for the active account
- **THEN** no freshness label is shown in the footer

### Requirement: Accessibility for refresh control
The refresh button SHALL have `.accessibilityLabel("Refresh usage")` and `.accessibilityValue` reflecting the current state (idle/refreshing/error reason).

#### Scenario: VoiceOver announces state
- **WHEN** VoiceOver focuses the refresh button
- **THEN** it announces "Refresh usage" and the current state value

