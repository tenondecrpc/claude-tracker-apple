## Why

The current watchOS app shows a single static view with concentric utilization rings and a text countdown. While functional, it underutilizes the Apple Watch form factor: there's no trend visualization, no session activity feedback, no complications for the watch face, and no use of Digital Crown or NavigationStack. Apple's watchOS HIG emphasizes glanceable, graphic-first interfaces with multiple focused views rather than one dense screen. Redesigning into 3-4 purpose-built views with a complication will make the app feel native and genuinely useful on the wrist.

## What Changes

- **Replace single ContentView with a TabView (`.verticalPage`)** containing 3 focused views navigable via Digital Crown swipe
- **New: Usage Dashboard view** — Redesigned primary ring with large center percentage, status color band, plan tier label, and extra-usage indicator. Replaces the current ContentView layout
- **New: 7-Day Trend view** — Horizontal bar chart showing daily utilization snapshots for the last 7 days, with today highlighted and a daily-average reference line. Requires history data from WatchConnectivity
- **New: Session Activity view** — Shows last session summary (tokens, cost, duration) with a live "active/idle" pulse indicator and haptic alert status icon
- **New: WidgetKit Complication** — Circular gauge accessory widget showing current 5h utilization percentage with color-coded fill, available on all watch faces that support accessory widgets
- **Extend WatchConnectivity payload** to include `usageHistory` (array of `UsageHistorySnapshot`) so the watch can render the 7-day trend without its own polling
- **Adopt `ClaudeCodeTheme` tokens** consistently across all new views (already migrated in the codebase)

## Capabilities

### New Capabilities
- `watch-trend-view`: 7-day horizontal bar chart view with daily utilization, today highlight, and average reference line
- `watch-session-view`: Last-session summary card with active/idle indicator and haptic status
- `watch-complication`: WidgetKit accessory circular gauge showing real-time 5h utilization
- `watch-tab-navigation`: Vertical-page TabView with Digital Crown navigation across 3 watch views

### Modified Capabilities
- `watch-dashboard`: Redesigned layout — large center percentage text, status color band, plan tier label, extra-usage badge; replaces text-only countdown center
- `watch-relay`: Extended payload to include `usageHistory: [UsageHistorySnapshot]` array for trend data delivery

## Impact

- **Watch Extension**: All 3 view files rewritten/new, `Claude_Tracker_WatchApp.swift` updated for TabView + WidgetKit
- **Shared models**: `UsageHistorySnapshot` already exists in `Shared/UsageHistoryModels.swift` — no new model needed
- **WatchConnectivity**: `WatchSessionReceiver.swift` must parse new `usageHistory` key; iOS sender must include history snapshots in `transferUserInfo`
- **iOS target**: The WatchConnectivity sender must bundle recent `UsageHistorySnapshot` entries alongside `UsageState`
- **New target**: watchOS Widget Extension for the complication
- **No breaking changes** to macOS or existing iCloud sync
