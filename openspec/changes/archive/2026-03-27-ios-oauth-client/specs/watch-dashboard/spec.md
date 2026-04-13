## MODIFIED Requirements

### Requirement: Mock badge is always visible during development
The dashboard SHALL display a `⚠ mock` badge whenever `usageState.isMocked == true`. The badge SHALL be persistently visible (not behind any tap or interaction). The badge SHALL disappear automatically when `isMocked` transitions to `false` - which occurs when the iOS relay delivers a real `UsageState` from the OAuth API.

#### Scenario: Mock state active
- **WHEN** `usageState.isMocked` is `true`
- **THEN** a `⚠ mock` label is visible on the dashboard

#### Scenario: Mock state inactive
- **WHEN** `usageState.isMocked` is `false`
- **THEN** no mock badge is displayed

#### Scenario: Badge disappears on first real data
- **WHEN** the iOS relay sends a `UsageState` with `isMocked: false` and the watch receives it
- **THEN** the `⚠ mock` badge is no longer visible on the watch dashboard
