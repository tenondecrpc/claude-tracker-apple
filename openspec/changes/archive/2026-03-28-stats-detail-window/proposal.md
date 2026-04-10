## Why

The menu bar popup (310pt wide) is too narrow to display detailed usage statistics comfortably. Users need a way to see richer, better-organized data — circular gauges, side-by-side session/weekly comparisons, and burn-rate details — in a proper window that uses the full screen width.

## What Changes

- Add a new "Stats Detail" window (~600×450) that opens from the existing "Usage History" button in the menu bar popup.
- Display Current Session (5h) and Weekly Limit (7d) side by side with large circular gauges.
- Show burn-rate indicator, last-polled timestamp with refresh, and account email in a full-width footer.
- Use `TimelineView` for live countdown updates in the detail window.

## Capabilities

### New Capabilities
- `stats-detail-window`: Standalone macOS window with two-column usage statistics layout, circular gauge components, and live countdown timers.

### Modified Capabilities
- `macos-menu-bar-ui`: The "Usage History" button becomes functional, opening the stats detail window via `openWindow(id:)`.

## Impact

- **New file**: `Tempo macOS/StatsDetailView.swift` — window content view and circular gauge component.
- **Modified**: `Tempo macOS/TempoMacApp.swift` — register new `Window` scene.
- **Modified**: `Tempo macOS/AuthenticatedView.swift` — wire "Usage History" button to `openWindow`.
- No dependency or API changes. Uses existing `MacAppCoordinator`, `UsageState`, and `ClaudeTheme`.
