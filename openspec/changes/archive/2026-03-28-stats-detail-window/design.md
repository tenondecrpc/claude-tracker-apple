## Context

The macOS menu bar popup is a 310pt-wide `.window`-style `MenuBarExtra`. The "Usage History" button opened this stats window in its first iteration. The first iteration delivers circular gauges, burn rate, and status bar using only the OAuth polling data already available. This design document covers the full roadmap toward feature parity with competitors, organized by data source dependency.

**Implementation tiers:**
- **Tier 1 (current)** - `UsagePoller` data only: gauges, burn rate with ETA, status bar
- **Tier 2** - Polling history store: time series chart
- **Tier 3** - `~/.claude/` local DB: activity heatmap, session stats table, per-project breakdown

## Goals / Non-Goals

**Goals:**
- Tier 1: Spacious window with circular gauges, burn rate ETA, live countdowns - no new data layer needed
- Tier 2: Time series chart from stored polling snapshots
- Tier 3: Full session analytics from `~/.claude/` local DB (Phase 8 in FUTURE_PLAN)

**Non-Goals:**
- Light mode support (stays dark-only)
- Cross-account or cross-machine aggregation
- Real-time per-session token tracking (requires Stop hook - Phase 3/4)

## Decisions

### 1. Window type: `Window` singleton (not `WindowGroup`)

Use `Window("Stats", id: "stats-detail")` - only one instance needed. `openWindow(id:)` brings it to front if already open.

### 2. Window sizing: resizable with minimum frame

Upgrade from fixed 600×450 to resizable with `minWidth: 700, minHeight: 550`. The chart and table sections need more vertical space. Use `ScrollView` for sections below the gauges.

**Previously**: Fixed non-resizable - too small for the full feature set.

### 3. Circular gauge: custom `Circle().trim` (Tier 1)

`ZStack` with track + trimmed fill circle. Lightweight and fully ClaudeTheme-compatible. No `import Charts` needed for gauges alone.

### 4. Time series chart: Swift Charts `LineMark` + `AreaMark` (Tier 2)

Use `import Charts` with `LineMark` for the Session series and `AreaMark` with opacity for the Weekly series. X axis: `Date` values. Y axis: 0–100 percentage.

**Data layer**: New `UsageHistory` class (Observable, macOS target only) backed by `~/.config/tempo-for-claude/usage-history.json`. `UsagePoller.onUsageState` callback appends a `UsageSnapshot` on every successful poll. Prune snapshots older than 30 days on each write.

```swift
struct UsageSnapshot: Codable {
    let date: Date
    let utilization5h: Double
    let utilization7d: Double
}
```

**Alternative**: CoreData - too heavy for simple time-series append. JSON array is sufficient.

### 5. `~/.claude/` local DB reading (Tier 3)

Phase 8 in FUTURE_PLAN.md establishes that `~/.claude/` contains full session history (209 sessions, model breakdown, project breakdown). Exact schema (SQLite vs JSON) to be confirmed in Phase 8 discovery. The stats window will read this via a new `ClaudeLocalDBReader` (macOS-only, non-blocking async read on a background task).

**Schema discovery needed before Tier 3 implementation**:
- File path: `~/.claude/` - exact subdirectory TBD
- Format: SQLite or JSON
- Fields: session timestamps, tokens per model, project names, tool calls, cost

### 6. `openWindow` + `NSApp.activate` from MenuBarExtra

`@Environment(\.openWindow)` works from `MenuBarExtra` content but requires `NSApp.activate(ignoringOtherApps: true)` immediately after the call to bring the window to front after the popup dismisses.

### 7. Scrollable layout for full feature set

The stats window content SHALL use a `ScrollView` wrapping a `VStack` of sections. The circular gauge section is pinned at the top (always visible); chart, heatmap, and table sections scroll below.

## Risks / Trade-offs

- **[Polling history size over time]** → Prune snapshots older than 30 days on each write. At 30-min polling, that's ~1,440 entries max - negligible JSON size (~100KB).
- **[`~/.claude/` DB schema change]** → Tier 3 implementation must be defensive with try/catch and graceful "unavailable" UI. Schema is internal to Claude Code and may change.
- **[Chart rendering performance]** → 1,440 points max. Swift Charts handles this without decimation. No performance risk.
- **[MenuBarExtra popup focus conflict]** → Resolved with `NSApp.activate(ignoringOtherApps: true)` after `openWindow(id:)`.
