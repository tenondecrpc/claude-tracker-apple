## ADDED Requirements

### Requirement: Usage ring displays 5-hour utilization
The dashboard SHALL display a circular progress ring representing `usageState.utilization5h` (0.0–1.0) as the primary glanceable element. The ring SHALL use a filled arc proportional to the utilization value.

#### Scenario: Ring at partial utilization
- **WHEN** `usageState.utilization5h` is 0.42
- **THEN** the ring arc covers 42% of the full circle

#### Scenario: Ring at zero utilization
- **WHEN** `usageState.utilization5h` is 0.0
- **THEN** the ring displays as empty (no filled arc)

#### Scenario: Ring at full utilization
- **WHEN** `usageState.utilization5h` is 1.0
- **THEN** the ring arc covers the full circle

### Requirement: Mock badge is always visible during development
The dashboard SHALL display a `⚠ mock` badge whenever `usageState.isMocked == true`. The badge SHALL be persistently visible (not behind any tap or interaction).

#### Scenario: Mock state active
- **WHEN** `usageState.isMocked` is `true`
- **THEN** a `⚠ mock` label is visible on the dashboard

#### Scenario: Mock state inactive
- **WHEN** `usageState.isMocked` is `false`
- **THEN** no mock badge is displayed

### Requirement: Reset countdown shows time remaining
The dashboard SHALL display a human-readable countdown to `usageState.resetAt5h` in the format "Xhr Ymin left". The countdown SHALL update live (at least once per minute).

#### Scenario: Hours and minutes remaining
- **WHEN** `resetAt5h` is 2 hours and 13 minutes in the future
- **THEN** the dashboard displays "2hr 13min left"

#### Scenario: Less than one hour remaining
- **WHEN** `resetAt5h` is 45 minutes in the future
- **THEN** the dashboard displays "45min left"

#### Scenario: Reset in the past
- **WHEN** `resetAt5h` is in the past
- **THEN** the dashboard displays "Resetting…" or "-"

### Requirement: Secondary 7-day utilization indicator
The dashboard SHALL display `usageState.utilization7d` as a secondary visual indicator (inner ring or badge). It SHALL be visually subordinate to the primary 5-hour ring.

#### Scenario: 7-day indicator present
- **WHEN** `usageState.utilization7d` is 0.18
- **THEN** a secondary indicator at 18% is visible alongside the main ring

### Requirement: Session completion sheet appears on pending completion
The dashboard SHALL present a full-screen sheet when `store.pendingCompletion` is non-nil. Dismissing the sheet SHALL set `pendingCompletion` to `nil`.

#### Scenario: Completion sheet shown
- **WHEN** `store.pendingCompletion` is set to a `SessionData` value
- **THEN** `CompletionView` is presented as a sheet

#### Scenario: Completion sheet dismissed
- **WHEN** the user dismisses `CompletionView`
- **THEN** `store.pendingCompletion` becomes `nil`
