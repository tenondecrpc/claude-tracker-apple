## ADDED Requirements

### Requirement: Stats detail window uses a horizontal top tab bar
The stats detail window (`DetailWindowView`) SHALL display a custom horizontal tab bar below the window title row. The tab bar SHALL contain four tabs in order: **Overview**, **Activity**, **Insights**, **Preferences**. The tab bar SHALL NOT be a macOS sidebar, `TabView`, or `NSTabView`-based control.

#### Scenario: Tab bar visible on open
- **WHEN** the stats detail window opens
- **THEN** the horizontal tab bar with all four tab labels is visible below the header

#### Scenario: Active tab is visually distinct
- **WHEN** a tab is selected
- **THEN** its label renders in `TempoTheme.accent` color with `.semibold` weight and an `accentMuted` background pill; all other tabs render in `TempoTheme.textSecondary` with regular weight

#### Scenario: Tab switching is animated
- **WHEN** the user clicks a different tab
- **THEN** the content area transitions with a `.easeInOut(duration: 0.2)` animation

### Requirement: Detail window minimum size is 900×780pt
The detail window SHALL have a minimum frame of 900pt wide by 780pt tall (previously 850×750pt).

#### Scenario: Window minimum size
- **WHEN** the user tries to resize the window below 900pt wide
- **THEN** the window stops at 900pt wide

### Requirement: Overview tab shows chart card and 2-column card grid
The Overview tab SHALL display:
1. A full-width chart card containing the existing Swift Charts area+line usage chart with time range picker and share button
2. A 2-column `LazyVGrid` of cards below the chart card:
   - **Session card**: mini concentric ring (same geometry as popover ring, 64×64pt), session percentage in `.title3.bold.monospacedDigit()`, reset time in `.footnote`, left-edge accent stripe in `TempoTheme.accent`
   - **Weekly card**: mini concentric ring, weekly percentage, reset day/time, left-edge stripe in `TempoTheme.info`
   - **Extra Usage card** (only when `extraUsage?.isEnabled == true`): dollar amounts `$X.XX / $Y.YY` in `.title3.bold.monospacedDigit()`, horizontal bar, "Resets monthly" caption, left-edge stripe in `TempoTheme.info`
   - **Burn Status card**: colored dot, burn assessment label, ETA to limit, left-edge stripe in status color

Cards use `TempoTheme.card` background, 12pt corner radius, 16pt padding, 4pt left-edge accent stripe.

#### Scenario: Chart card present in Overview
- **WHEN** the Overview tab is selected
- **THEN** the full-width chart card with time range picker is visible at the top

#### Scenario: Four cards in 2-column grid
- **WHEN** Extra Usage is enabled and Overview tab is selected
- **THEN** four cards appear in two columns: Session, Weekly, Extra Usage, Burn Status

#### Scenario: Extra Usage card hidden when disabled
- **WHEN** Extra Usage is disabled and Overview tab is selected
- **THEN** only three cards appear: Session, Weekly, Burn Status

### Requirement: Activity tab merges heatmap and Claude Code stats
The Activity tab SHALL display:
1. The 52-week activity heatmap at the top (same component as current `ActivityHeatmapView`)
2. The Claude Code aggregate stats row below (messages, tool calls, sessions, API cost, subagents, model token breakdowns)
3. The Claude Code project table below the aggregate row (same structure as current)
A "7 days" accent chip SHALL label the Claude Code section header.

#### Scenario: Activity tab shows merged content
- **WHEN** the Activity tab is selected
- **THEN** the heatmap and Claude Code stats table are both visible in a single scroll view

### Requirement: Insights tab shows warning, subscription, and stat cards
The Insights tab SHALL display the existing insights content with more vertical breathing room:
1. The burn rate warning card (full width)
2. The subscription value card (full width)
3. The four compact stat cards in a row (Avg Session, Avg Weekly, High Usage Days, Peak Session)

#### Scenario: Insights tab shows all insight cards
- **WHEN** the Insights tab is selected
- **THEN** all six insight elements are visible with 24pt section spacing

### Requirement: Detail window header shows only title and account info
The detail window header SHALL display:
- Left: "Tempo for Claude" title in `.title3.weight(.semibold)`
- Right: account email in `.callout` in `TempoTheme.textSecondary`
- The gear settings icon SHALL be removed from the header entirely

#### Scenario: No gear icon in header
- **WHEN** the detail window is open
- **THEN** there is no gear/settings button visible in the header row
