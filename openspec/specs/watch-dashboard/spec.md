## ADDED Requirements

### Requirement: Dashboard displays account label from iPhone relay
The watch dashboard SHALL display a compact account label (email prefix or display name) in its header, sourced from the `accountLabel` field of the most recent `updateApplicationContext` payload. Tapping the label SHALL show the full email or display name in a sheet. The watch SHALL NOT provide any account picker control.

#### Scenario: Active account label visible
- **WHEN** the iPhone has active account `user@example.com` and relays an application context update
- **THEN** the watch dashboard shows `user` (or a configured short form) in its header

#### Scenario: Full label on tap
- **WHEN** the user taps the account label in the dashboard header
- **THEN** a sheet presents the full email or display name

#### Scenario: No active account state
- **WHEN** the last received payload had `"type": "NoActiveAccount"`
- **THEN** the dashboard shows a "No accounts available - check Mac app" state and hides the usage ring

### Requirement: Active account change clears stale state
When the received `accountId` differs from the `accountId` the watch currently renders, the watch SHALL discard its previous `usageState` and `pendingCompletion` state before rendering the new account's data. The mock badge policy SHALL still follow `isMocked` on the incoming `UsageState`.

#### Scenario: Switch account clears prior state
- **WHEN** the watch receives a context update with `accountId = B` while it was displaying `accountId = A`
- **THEN** the dashboard immediately switches to account B and any `pendingCompletion` tied to account A is dismissed

#### Scenario: Same account refresh preserves state
- **WHEN** a context update arrives for the same `accountId` currently displayed
- **THEN** the usage ring updates but no pending completion sheet is dismissed
## Requirements
### Requirement: Dashboard hosts compact footer with timestamp and refresh
The dashboard SHALL embed a compact footer row below the usage ring containing the freshness timestamp on the left and the refresh button on the right. The ring center contains only the percentage and "5H" label (no timestamp inside the ring). This maximizes ring size on the small watch display.

#### Scenario: Compact footer visible below ring
- **WHEN** the dashboard renders with any state
- **THEN** a single-line footer with timestamp (left) and refresh icon (right) is visible below the ring

### Requirement: Freshness indicator uses compact format in footer
The dashboard SHALL display a compact relative time label in the footer (left side) using the format: "now" (< 60s), "Xm" (minutes), "Xh" (hours). A small clock icon precedes the text. The label is driven by `TokenStore.lastRelayReceivedAtForActiveAccount`.

#### Scenario: Freshness label in footer with recent data
- **WHEN** the last relay was received less than 60 seconds ago
- **THEN** the footer shows a clock icon followed by "now"

#### Scenario: Freshness label with stale data
- **WHEN** the last relay was received 5 minutes ago
- **THEN** the footer shows a clock icon followed by "5m"

