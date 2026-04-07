## ADDED Requirements

### Requirement: Popover uses concentric ring gauges as hero element
The authenticated menu bar popover SHALL display a concentric ring gauge as its primary visual element. The gauge SHALL consist of:
- **Outer ring**: weekly utilization, stroke color `TempoTheme.info` (sky blue), lineWidth 8pt, `lineCap .round`
- **Inner ring**: session utilization, stroke color `TempoTheme.accent` (electric violet), lineWidth 10pt, `lineCap .round`, inset from outer ring by 18pt padding
- **Track rings**: both outer and inner tracks SHALL use `TempoTheme.progressTrack` at full opacity behind their fill rings
- **Center label**: session percentage as `Int` rendered in `.system(size: 28, weight: .bold, design: .rounded)` in `TempoTheme.textPrimary`, with "session" label in `.caption2` in `TempoTheme.textSecondary` directly below
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

### Requirement: Popover width is 320pt
The `MenuBarExtra` window body SHALL have a fixed width of 320pt (previously 310pt).

#### Scenario: Popover width
- **WHEN** the menu bar icon is clicked
- **THEN** the popover window measures 320pt wide

### Requirement: Popover shows pill chips for session and weekly summaries
Below the ring gauge, the popover SHALL show two horizontally-arranged pill chips:
- **Session chip**: left-edge 3pt accent stripe in `TempoTheme.accent`, shows session percentage and reset time (e.g., "42% · 2h 13m"), formatted per 24h preference
- **Weekly chip**: left-edge 3pt accent stripe in `TempoTheme.info`, shows weekly percentage (e.g., "18%"), formatted per 24h preference
- Chips use `TempoTheme.surface` background, 8pt corner radius, `.callout.monospacedDigit()` for values, `.footnote` for labels

#### Scenario: Chips display correct values
- **WHEN** `utilization5h = 0.42`, reset in 2h 13m, `utilization7d = 0.18`
- **THEN** the session chip shows "42% · 2h 13m" and the weekly chip shows "18%"

### Requirement: Burn rate card replaces inline text
The burn rate status SHALL be displayed in a card component with `TempoTheme.card` background and 12pt corner radius. The card SHALL contain:
- A colored status dot: `TempoTheme.success` (on track) or `TempoTheme.warning` (high burn)
- Burn rate label: "On track" or "High burn" with rate in %/hr (e.g., "On track · 10.5%/hr") in `.callout`
- Reset countdown below: "Resets in 2h 13m (20:00)" in `.footnote` in `TempoTheme.textSecondary`
- A `DisclosureGroup` at the bottom for Extra Usage (see extra-usage spec)

#### Scenario: On track burn rate
- **WHEN** burn rate assessment is on track
- **THEN** the card shows a teal-green dot and "On track · X%/hr"

#### Scenario: High burn rate
- **WHEN** burn rate assessment is high burn
- **THEN** the card shows an amber dot and "High burn · X%/hr"

### Requirement: Service status is a single dot in the popover header
The service status indicator SHALL appear as a single 8pt circle in the popover header row, immediately left of the refresh button. Color SHALL map to `ServiceHealthState`:
- `.operational`: `TempoTheme.success`
- `.degraded`: `TempoTheme.warning`
- `.majorOutage`: `TempoTheme.critical`
- `.stale` / `.unavailable`: `TempoTheme.textSecondary`

The status SHALL NOT appear as a separate row in the popover body.

#### Scenario: Service status dot visible in header
- **WHEN** service monitoring is enabled and status is operational
- **THEN** a teal-green dot appears in the header next to the refresh icon

#### Scenario: Service status not in body
- **WHEN** the authenticated popover is displayed
- **THEN** there is no "Claude Code: Operational" row in the popover body

### Requirement: Popover header branding updated to "Tempo"
The popover header title SHALL display "Tempo" (not "Usage for Claude"). Font remains the same `.headline` weight.

#### Scenario: Header shows Tempo
- **WHEN** the menu bar popover opens
- **THEN** the header title reads "Tempo"
