## MODIFIED Requirements

### Requirement: Usage ring displays 5-hour utilization
The dashboard SHALL display a circular progress ring representing `usageState.utilization5h` (0.0–1.0) as the primary glanceable element. The ring SHALL use a filled arc proportional to the utilization value. The ring stroke SHALL be 8pt with `.round` line cap.

#### Scenario: Ring at partial utilization
- **WHEN** `usageState.utilization5h` is 0.42
- **THEN** the ring arc covers 42% of the full circle

#### Scenario: Ring at zero utilization
- **WHEN** `usageState.utilization5h` is 0.0
- **THEN** the ring displays as empty (no filled arc), only the track is visible

#### Scenario: Ring at full utilization
- **WHEN** `usageState.utilization5h` is 1.0
- **THEN** the ring arc covers the full circle

### Requirement: Large center percentage display
The dashboard SHALL display the current 5h utilization as a large percentage number centered inside the ring. The text SHALL use `.system(.title, design: .rounded)` font with `.semibold` weight. The percentage SHALL be formatted as an integer (e.g., "42%") without decimal places.

#### Scenario: Percentage matches utilization
- **WHEN** `usageState.utilization5h` is 0.42
- **THEN** the center displays "42%"

#### Scenario: Zero utilization
- **WHEN** `usageState.utilization5h` is 0.0
- **THEN** the center displays "0%"

#### Scenario: Over-limit utilization
- **WHEN** `usageState.utilization5h` is 1.0
- **THEN** the center displays "100%"

### Requirement: Status color band on ring
The primary ring color SHALL reflect the utilization severity: `ClaudeCodeTheme.success` for utilization < 0.6, `ClaudeCodeTheme.warning` for 0.6–0.85, `ClaudeCodeTheme.error` for >= 0.85. The center percentage text SHALL use the same color as the ring.

#### Scenario: Low utilization color
- **WHEN** `usageState.utilization5h` is 0.30
- **THEN** the ring and percentage text use `ClaudeCodeTheme.success` (green)

#### Scenario: Medium utilization color
- **WHEN** `usageState.utilization5h` is 0.72
- **THEN** the ring and percentage text use `ClaudeCodeTheme.warning` (amber)

#### Scenario: High utilization color
- **WHEN** `usageState.utilization5h` is 0.90
- **THEN** the ring and percentage text use `ClaudeCodeTheme.error` (red)

### Requirement: Reset countdown as secondary label
The dashboard SHALL display the countdown to `usageState.resetAt5h` below the ring as a caption-sized label using `ClaudeCodeTheme.textSecondary`. Format: "Xhr Ymin" (no "left" suffix to save space). The countdown SHALL update at least once per minute via `TimelineView`.

#### Scenario: Hours and minutes remaining
- **WHEN** `resetAt5h` is 2 hours and 13 minutes in the future
- **THEN** the label below the ring displays "2hr 13min"

#### Scenario: Less than one hour
- **WHEN** `resetAt5h` is 45 minutes in the future
- **THEN** the label displays "45min"

#### Scenario: Reset imminent or past
- **WHEN** `resetAt5h` is in the past
- **THEN** the label displays "Resetting…"

### Requirement: Secondary 7-day utilization indicator
The dashboard SHALL display `usageState.utilization7d` as an inner ring (4pt stroke) using `ClaudeCodeTheme.highlight`. It SHALL be visually subordinate to the primary ring.

#### Scenario: 7-day indicator present
- **WHEN** `usageState.utilization7d` is 0.18
- **THEN** a secondary inner ring at 18% is visible inside the main ring

### Requirement: Extra-usage badge
The dashboard SHALL display a small pill badge labeled "Extra" using `ClaudeCodeTheme.info` when `usageState.isUsingExtraUsage` is true. The badge SHALL appear below the countdown label.

#### Scenario: Extra usage active
- **WHEN** `usageState.isUsingExtraUsage` is true
- **THEN** a blue "Extra" pill badge is visible below the countdown

#### Scenario: Extra usage not active
- **WHEN** `usageState.isUsingExtraUsage` is false
- **THEN** no extra-usage badge is displayed

### Requirement: Mock badge is always visible during development
The dashboard SHALL display a `⚠ mock` badge whenever `usageState.isMocked == true`. The badge SHALL use `ClaudeCodeTheme.accent` foreground color.

#### Scenario: Mock state active
- **WHEN** `usageState.isMocked` is `true`
- **THEN** a `⚠ mock` label is visible on the dashboard

#### Scenario: Mock state inactive
- **WHEN** `usageState.isMocked` is `false`
- **THEN** no mock badge is displayed
