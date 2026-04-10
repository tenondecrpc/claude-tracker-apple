## Tier 1 — OAuth data only (no new data layer)

- [x] 1.1 Create `CircularGauge` view in `StatsDetailView.swift` with `Circle().trim` track + fill, rounded line caps, ~12pt line width, ClaudeTheme colors
- [x] 1.2 Center percentage text inside the gauge as bold title-size text
- [x] 1.3 Create `StatsDetailView` in `Tempo macOS/StatsDetailView.swift` receiving `MacAppCoordinator`
- [x] 1.4 Implement two-column `HStack` layout: left column (Current Session 5h gauge + reset countdown), right column (Weekly Limit 7d gauge + reset date)
- [x] 1.5 Add full-width burn-rate section with on-track/high-burn indicator and `UsageProgressBar`
- [x] 1.6 Add ETA label to burn rate section: "At current rate, you'll hit the limit in ~X hours" (visible only when High burn)
- [x] 1.7 Add status bar with last-polled relative timestamp, refresh button with spinner, and account email
- [x] 1.8 Wrap content in `TimelineView(.periodic(from: .now, by: 30))` for live countdown updates
- [x] 1.9 Apply `.preferredColorScheme(.dark)` and `ClaudeTheme.background`
- [x] 1.10 Add `Window("Stats", id: "stats-detail")` scene in `TempoMacApp.swift` with `.windowResizability(.contentSize)`
- [x] 1.11 Wire "Usage History" button in `AuthenticatedView.swift` to `openWindow(id: "stats-detail")` + `NSApp.activate`

## Tier 2 — Polling history store + time series chart

- [x] 2.1 Create `UsageSnapshot` struct in `Tempo macOS/UsageHistory.swift` (date, utilization5h, utilization7d)
- [x] 2.2 Create `UsageHistory` Observable class: load/save JSON at `~/.config/tempo-for-claude/usage-history.json`, append snapshot, prune entries older than 30 days
- [x] 2.3 Wire `UsagePoller.onUsageState` callback to append snapshot to `UsageHistory` after each successful poll
- [x] 2.4 Pass `UsageHistory` instance through `MacAppCoordinator` to `StatsDetailView`
- [x] 2.5 Add `import Charts` and implement `LineChart` section in `StatsDetailView`: `LineMark` for Session (blue), `AreaMark` for Weekly (coral fill with opacity)
- [x] 2.6 Add X axis with HH:MM time labels and Y axis with 0/25/50/75/100% marks
- [x] 2.7 Add Session/Weekly legend with toggle checkboxes below chart
- [x] 2.8 Add "Export CSV" button that writes snapshot history to a user-selected file via `NSSavePanel`
- [x] 2.9 Show "No history yet" placeholder when `UsageHistory.snapshots` is empty
- [x] 2.10 Update window min frame to 700×550 and add `ScrollView` wrapper around sections below gauges

## Tier 3 — `~/.claude/` local DB (Phase 8)

> **Prerequisite**: Confirm `~/.claude/` DB schema (file path, format, field names) before implementing any task in this tier.

- [x] 3.1 Create `ClaudeLocalDBReader` in `Tempo macOS/` — async read of `~/.claude/` session DB, decode sessions with timestamps, project names, token counts per model, tool calls, cost
- [x] 3.2 Implement activity heatmap view: grid of cells (day-of-week × week columns, ~12 months), fill intensity from session count, `ClaudeTheme.accent` with opacity levels
- [x] 3.3 Implement 4 stat cards (Avg Session, Avg Weekly, High Usage days, Peak) computed from DB history
- [x] 3.4 Implement "Claude Code (7 days)" aggregate row: Messages, Tool Calls, Sessions, API Cost Equiv., Subagents
- [x] 3.5 Implement model breakdown row: Opus / Sonnet / Haiku token counts
- [x] 3.6 Implement per-project table: Project, Sessions, Messages, Tools, Tokens, Cost — sorted by tokens desc
- [x] 3.7 Add graceful "unavailable" state for all Tier 3 sections when DB not found or unreadable
