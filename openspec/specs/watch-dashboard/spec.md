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
### Requirement: Dashboard hosts refresh button footer
The dashboard SHALL embed the refresh button described in `watch-refresh-ui` in a centered footer row below the usage ring. The footer SHALL be part of the main dashboard layout, not a floating overlay.

#### Scenario: Footer visible below ring
- **WHEN** the dashboard renders with any state
- **THEN** the refresh button footer is visible below the ring

### Requirement: Dashboard shows freshness indicator inside ring center
The dashboard SHALL display a compact "Updated Xm ago" label inside the ring's center VStack, below the metric labels. The label is driven by `TokenStore.lastRelayReceivedAt`.

#### Scenario: Freshness label positioned inside ring
- **WHEN** the dashboard renders with a known last-relay timestamp
- **THEN** the "Updated Xm ago" label appears inside the ring center below "5H"

