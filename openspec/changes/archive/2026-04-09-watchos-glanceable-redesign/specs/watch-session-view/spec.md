## ADDED Requirements

### Requirement: Last session summary card
The Session view SHALL display a card showing the most recent session's key metrics: total tokens (input + output), cost in USD, and duration. The card SHALL use `ClaudeCodeTheme.card` background with rounded corners (12pt radius).

#### Scenario: Session data available
- **WHEN** `store.sessions` contains at least one entry and the most recent is `SessionInfo(inputTokens: 4200, outputTokens: 1800, costUSD: 0.12, durationSeconds: 142)`
- **THEN** the card displays "6,000 tokens", "$0.12", and "2m 22s"

#### Scenario: No session data
- **WHEN** `store.sessions` is empty
- **THEN** the view displays a centered SF Symbol `bubble.left.and.text.bubble.right` with caption "No sessions yet" in `ClaudeCodeTheme.textTertiary`

### Requirement: Token count as primary metric
The total token count (input + output) SHALL be displayed as the largest text element using `.system(.title3, design: .rounded)` with `.semibold` weight in `ClaudeCodeTheme.textPrimary`. Values over 1,000 SHALL use abbreviated format with "K" suffix (e.g., "6.0K tokens").

#### Scenario: Small token count
- **WHEN** total tokens is 450
- **THEN** "450 tokens" is displayed

#### Scenario: Large token count
- **WHEN** total tokens is 12,500
- **THEN** "12.5K tokens" is displayed

### Requirement: Cost and duration as secondary metrics
Cost and duration SHALL be displayed in a horizontal row below the token count using `.system(.caption, design: .rounded)` font in `ClaudeCodeTheme.textSecondary`. Cost SHALL use USD currency format. Duration SHALL use compact format (e.g., "2m 22s").

#### Scenario: Metrics formatting
- **WHEN** cost is 0.12 and duration is 142 seconds
- **THEN** "$0.12" and "2m 22s" are displayed side by side

### Requirement: Activity status indicator
The Session view SHALL display a status indicator below the session card showing whether a session is currently active. An SF Symbol `circle.fill` (6pt) SHALL pulse with animation when a session was active within the last 5 minutes (based on the most recent session's timestamp), using `ClaudeCodeTheme.success`. When idle, the dot SHALL be static using `ClaudeCodeTheme.textTertiary` with label "Idle".

#### Scenario: Recently active
- **WHEN** the most recent session's timestamp is less than 5 minutes ago
- **THEN** a green pulsing dot is displayed with label "Active"

#### Scenario: Idle
- **WHEN** the most recent session's timestamp is more than 5 minutes ago
- **THEN** a grey static dot is displayed with label "Idle"

#### Scenario: No sessions
- **WHEN** no sessions exist
- **THEN** a grey static dot is displayed with label "Idle"

### Requirement: Haptic alert status icon
The Session view SHALL display an SF Symbol indicating haptic notification status: `bell.fill` in `ClaudeCodeTheme.accent` when notifications are active (default), `bell.slash` in `ClaudeCodeTheme.textTertiary` when silenced. This is a read-only indicator reflecting whether the completion sheet fires.

#### Scenario: Haptics enabled (default)
- **WHEN** haptic alerts are enabled (always true in current implementation)
- **THEN** `bell.fill` icon is displayed in accent color

### Requirement: Session timestamp
The Session view SHALL display the last session's timestamp as a relative time label (e.g., "2 min ago", "1 hr ago") using `.system(.caption2)` font in `ClaudeCodeTheme.textTertiary`. The label SHALL update at least once per minute via `TimelineView`.

#### Scenario: Recent session
- **WHEN** the last session was 3 minutes ago
- **THEN** "3 min ago" is displayed

#### Scenario: Older session
- **WHEN** the last session was 2 hours ago
- **THEN** "2 hr ago" is displayed
