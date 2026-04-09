## ADDED Requirements

### Requirement: iOS dashboard renders macOS-equivalent usage overview
The iOS app SHALL provide a dashboard experience that mirrors macOS overview insights using iCloud-backed `UsageState`: primary 5-hour usage ring, secondary 7-day usage indicator, reset-time messaging, and burn-rate context.

#### Scenario: Fresh usage snapshot renders core metrics
- **WHEN** iCloud provides `utilization5h = 0.42`, `utilization7d = 0.18`, and valid reset timestamps
- **THEN** the dashboard shows 42% primary usage, 18% secondary usage, and both reset-time labels

#### Scenario: Dashboard updates from iCloud without manual refresh
- **WHEN** a newer `usage.json` is detected by iCloud metadata updates
- **THEN** the dashboard metrics update to the new values in the same app session

### Requirement: iOS dashboard shows promo and extra-usage context
The dashboard SHALL display promo and extra-usage information equivalent to macOS when present in `UsageState`, including active promo badge and extra-usage credit context.

#### Scenario: Double-limit promo is active
- **WHEN** `isDoubleLimitPromoActive` is `true` in the latest iCloud `UsageState`
- **THEN** the dashboard shows a visible promo indicator above the primary usage visualization

#### Scenario: Extra usage is enabled
- **WHEN** `extraUsage.isEnabled` is `true` and credits are present
- **THEN** the dashboard shows extra-usage consumption details as a dedicated section/card

### Requirement: Dashboard provides explicit sync-state UX
The iOS dashboard SHALL expose clear waiting, syncing, and stale states based on iCloud freshness so users understand whether data is current.

#### Scenario: No iCloud usage file yet
- **WHEN** `usage.json` has not been discovered or downloaded
- **THEN** the dashboard shows a waiting/connection guidance state instead of empty metrics

#### Scenario: Usage data is stale
- **WHEN** the last successfully decoded usage snapshot is older than 30 minutes
- **THEN** the dashboard shows a stale warning with relative "last updated" information

### Requirement: Dashboard visual system uses Claude palette tokens
All dashboard surfaces SHALL use `ClaudeCodeTheme` token colors for backgrounds, cards, typography, accents, borders, and status cues.

#### Scenario: Accent-driven controls and highlights
- **WHEN** dashboard controls, pills, or primary indicators are rendered
- **THEN** they use `ClaudeCodeTheme` accent/status tokens instead of ad-hoc platform default colors

#### Scenario: Background and card hierarchy match Claude theme
- **WHEN** the dashboard appears
- **THEN** root background and nested cards use `ClaudeCodeTheme.background` and `ClaudeCodeTheme.card` respectively
