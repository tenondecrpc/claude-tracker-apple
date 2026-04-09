## MODIFIED Requirements

### Requirement: Popover uses concentric ring gauges as hero element
The authenticated menu bar popover SHALL display a concentric ring gauge as its primary visual element. The gauge SHALL consist of:
- **Outer ring**: weekly utilization, stroke color `ClaudeCodeTheme.info` (blue), lineWidth 8pt, `lineCap .round`
- **Inner ring**: session utilization, stroke color `ClaudeCodeTheme.accent` (terracotta), lineWidth 10pt, `lineCap .round`, inset from outer ring by 18pt padding
- **Track rings**: both outer and inner tracks SHALL use `ClaudeCodeTheme.progressTrack` at full opacity behind their fill rings
- **Center label**: session percentage as `Int` rendered in `.system(size: 28, weight: .bold, design: .rounded)` in `ClaudeCodeTheme.textPrimary`, with "session" label in `.caption2` in `ClaudeCodeTheme.textSecondary` directly below
- Total ring frame: 150×150pt, centered horizontally in the popover

#### Scenario: Rings reflect live data
- **WHEN** the poller reports `utilization5h = 0.42` and `utilization7d = 0.18`
- **THEN** the inner ring arc covers 42% of the circle and the outer ring arc covers 18% of the circle

#### Scenario: Center label shows session percentage
- **WHEN** `utilization5h = 0.42`
- **THEN** the center text reads "42" in rounded bold font with "session" label below

#### Scenario: Rings start at 12 o'clock
- **WHEN** any utilization > 0
- **THEN** the arc fill begins at the top (−90° rotation) and sweeps clockwise

### Requirement: Popover shows pill chips for session and weekly summaries
Below the ring gauge, the popover SHALL show two horizontally-arranged pill chips:
- **Session chip**: left-edge 3pt accent stripe in `ClaudeCodeTheme.accent`, shows session percentage and reset time (e.g., "42% · 2h 13m"), formatted per 24h preference
- **Weekly chip**: left-edge 3pt accent stripe in `ClaudeCodeTheme.info`, shows weekly percentage (e.g., "18%"), formatted per 24h preference
- Chips use `ClaudeCodeTheme.surface` background, 8pt corner radius, `.callout.monospacedDigit()` for values, `.footnote` for labels

#### Scenario: Chips display correct values
- **WHEN** `utilization5h = 0.42`, reset in 2h 13m, `utilization7d = 0.18`
- **THEN** the session chip shows "42% · 2h 13m" and the weekly chip shows "18%"

### Requirement: Burn rate card replaces inline text
The burn rate status SHALL be displayed in a card component with `ClaudeCodeTheme.card` background and 12pt corner radius. The card SHALL contain:
- A colored status dot: `ClaudeCodeTheme.success` (on track) or `ClaudeCodeTheme.warning` (high burn)
- Burn rate label: "On track" or "High burn" with rate in %/hr (e.g., "On track · 10.5%/hr") in `.callout`
- Reset countdown below: "Resets in 2h 13m (20:00)" in `.footnote` in `ClaudeCodeTheme.textSecondary`
- A `DisclosureGroup` at the bottom for Extra Usage (see extra-usage spec)

#### Scenario: On track burn rate
- **WHEN** burn rate assessment is on track
- **THEN** the card shows a green dot and "On track · X%/hr"
