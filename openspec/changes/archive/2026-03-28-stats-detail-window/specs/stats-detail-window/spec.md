## Data Source Map

Features in this spec depend on three distinct data sources with different implementation costs:

| Label | Source | Status |
|-------|--------|--------|
| `[OAUTH]` | `UsagePoller` - current `utilization5h/7d`, `resetAt5h/7d` | ✅ Available now |
| `[HISTORY]` | Polling snapshots stored locally (new `UsageHistory` store) | 🔴 Needs new data layer |
| `[LOCALDB]` | `~/.claude/` session DB - sessions, messages, tokens, cost, model breakdown | 🟡 Phase 8 in FUTURE_PLAN |

---

## ADDED Requirements

### Requirement: Stats detail window registered as singleton scene
The app SHALL register a `Window("Stats", id: "stats-detail")` scene that displays `StatsDetailView` with the app coordinator. The window SHALL be resizable with a minimum frame of approximately 700×550.

#### Scenario: Window opens from menu bar
- **WHEN** the user clicks "Usage History" in the authenticated menu bar popup
- **THEN** a "Stats" window opens (or comes to front if already open) showing detailed usage statistics

#### Scenario: Only one instance exists
- **WHEN** the user clicks "Usage History" while the stats window is already open
- **THEN** the existing window comes to front; no second window is created

---

### Requirement: Two-column layout with circular gauges `[OAUTH]`
The stats detail window SHALL display two columns side by side:
1. **Left column - Current Session (5h)**: A large circular gauge showing `utilization5h`, the percentage as bold text inside the gauge, a "Current Session" label, and a reset countdown ("Resets in X min (HH:MM)").
2. **Right column - Weekly Limit (7d)**: A large circular gauge showing `utilization7d`, the percentage as bold text inside the gauge, a "Weekly Limit" label, and a reset date ("Resets EEE, HH:mm").

Each circular gauge SHALL use a `Circle().trim` arc with `ClaudeTheme.accent` fill over a `ClaudeTheme.progressTrack` track, with rounded line caps and a line width of approximately 12 points.

#### Scenario: Session gauge reflects current utilization
- **WHEN** `utilization5h = 0.65` and `resetAt5h` is 42 minutes from now at 18:30
- **THEN** the left column shows a circular gauge filled to 65%, "65%" text centered, "Current Session" label, and "Resets in 42 min (18:30)"

#### Scenario: Weekly gauge reflects current utilization
- **WHEN** `utilization7d = 0.12` and `resetAt7d` is next Wednesday at 09:00
- **THEN** the right column shows a circular gauge filled to 12%, "12%" text centered, "Weekly Limit" label, and "Resets Wed, 09:00"

---

### Requirement: Burn rate section with ETA `[OAUTH]`
Below the two columns, a full-width section SHALL display:
1. A burn-rate label showing "On track" (green) or "High burn" (orange) with the hourly rate in `%/hr`, using the 20%/hr threshold.
2. A horizontal `UsageProgressBar` showing the 5h utilization.
3. **Time-to-limit estimate**: when at high burn, a secondary label SHALL show "At current rate, you'll hit the limit in ~X hours" using `(1.0 - utilization5h) / burnRatePerHour`.

#### Scenario: High burn rate with ETA
- **WHEN** `utilization5h = 0.91` and burn rate is 27.2%/hr
- **THEN** the section shows "High burn · 27.2%/hr" and "At current rate, you'll hit the limit in ~0.3 hours"

#### Scenario: On-track no ETA shown
- **WHEN** burn rate is 8.5%/hr
- **THEN** the section shows "On track · 8.5%/hr" with no ETA label

---

### Requirement: Status bar with last-polled and refresh `[OAUTH]`
The window SHALL display a bottom status bar showing:
1. The last-polled relative timestamp (e.g., "Updated 3 min ago")
2. A refresh button that triggers `poller.pollNow()` and shows a spinner while polling
3. The account email if available, displayed as secondary text

#### Scenario: Refresh from stats window
- **WHEN** the user clicks the refresh button in the stats detail window
- **THEN** `pollNow()` is called, the button shows a spinner, and data updates when the poll completes

#### Scenario: Account email shown
- **WHEN** `authState.accountEmail` is "user@example.com"
- **THEN** the status bar displays "user@example.com" in secondary text

---

### Requirement: Live countdown updates `[OAUTH]`
The stats detail window SHALL use `TimelineView(.periodic(from: .now, by: 30))` to update reset countdowns every 30 seconds without requiring a new API poll.

#### Scenario: Countdown ticks down
- **WHEN** 30 seconds pass without a new poll
- **THEN** the reset countdown text updates to reflect the new remaining time

---

### Requirement: Usage time series chart `[HISTORY]`
The stats detail window SHALL display a scrollable line chart showing the history of `utilization5h` (Session, blue line) and `utilization7d` (Weekly, filled area) over time. The X axis SHALL show time labels in HH:MM format; the Y axis SHALL show 0–100% in 25% increments. A legend with toggle checkboxes for Session and Weekly SHALL appear below the chart. An "Export CSV" button SHALL allow the user to save the snapshot history.

**Data layer**: Requires a new `UsageHistory` store that appends a `UsageSnapshot(date: Date, utilization5h: Double, utilization7d: Double)` to a local JSON file on each successful poll. The `UsagePoller` SHALL notify the store via a callback after every successful fetch.

#### Scenario: Chart shows historical trend
- **WHEN** the window opens and 10 polling snapshots are stored
- **THEN** a line chart is displayed with time on X and utilization % on Y, showing both series

#### Scenario: No history yet
- **WHEN** the window opens and no snapshots are stored
- **THEN** a placeholder "No history yet - check back after the next poll" is shown in place of the chart

#### Scenario: Legend toggle hides a series
- **WHEN** the user unchecks "Weekly" in the legend
- **THEN** only the Session line is rendered in the chart

---

### Requirement: Usage Activity heatmap `[LOCALDB]`
The stats detail window SHALL display a GitHub-style activity heatmap grid showing session activity by day of week (rows: Mon/Wed/Fri sampled) and week (columns spanning ~12 months). Each cell's fill intensity SHALL represent relative session activity for that day. Cells with no activity SHALL use `ClaudeTheme.progressTrack`.

**Data layer**: Read session timestamps from `~/.claude/` local DB (Phase 8 in FUTURE_PLAN). Schema to be confirmed during Phase 8 discovery.

#### Scenario: Active days shown with fill
- **WHEN** the local DB contains 5 sessions on a given Friday
- **THEN** that cell renders with high-intensity `ClaudeTheme.accent` fill

#### Scenario: Inactive days shown as track color
- **WHEN** no sessions occurred on a given Monday
- **THEN** that cell renders with `ClaudeTheme.progressTrack`

---

### Requirement: Summary stat cards `[LOCALDB]`
Below the heatmap, the window SHALL display four stat cards in a 2×2 grid:
1. **Avg Session** - average `utilization5h` at session end across the last 30 days
2. **Avg Weekly** - average `utilization7d` across the last 4 complete weeks
3. **High Usage** - count of days where peak utilization exceeded 90%
4. **Peak** - highest single-session utilization ever recorded

#### Scenario: Stat cards show historical values
- **WHEN** the local DB has 30 days of history
- **THEN** each card shows its computed value derived from that history

---

### Requirement: Claude Code session stats table `[LOCALDB]`
The stats detail window SHALL display a "Claude Code (7 days)" section with:
1. **Aggregate row**: total Messages, Tool Calls, Sessions, API Cost Equivalent, Subagents count
2. **Model breakdown**: token counts for Opus, Sonnet, Haiku
3. **Per-project table**: columns Project, Sessions, Messages, Tools, Tokens, Cost - sorted by token count descending

**Data layer**: Read from `~/.claude/` local DB (same Phase 8 DB as heatmap). Schema and exact file path to be confirmed in Phase 8 discovery.

#### Scenario: Per-project breakdown shown
- **WHEN** the local DB has sessions across 3 projects in the last 7 days
- **THEN** a table with 3 rows appears, sorted by token count descending

#### Scenario: No local DB found
- **WHEN** `~/.claude/` does not contain a readable session DB
- **THEN** the section shows "Claude Code history unavailable - local DB not found"

---

### Requirement: Dark theme applied to stats window
The stats detail window SHALL use `.preferredColorScheme(.dark)` with `ClaudeTheme` colors matching the menu bar popup aesthetic.

#### Scenario: Window uses dark appearance
- **WHEN** the stats detail window opens regardless of system appearance
- **THEN** the window renders with dark navy background (`ClaudeTheme.background`) and light text
