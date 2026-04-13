## Why

The usage chart offers fixed time windows (5h, 24h, 7d, 30d, 90d) but users sometimes want to zoom into a specific date range - e.g., investigate a spike on a particular day. The `TimeRange.custom` case already exists in the enum but has no UI or filtering logic.

## What Changes

- Show two `DatePicker` controls inline in the chart header when the user selects "Custom"
- Wire `filteredSnapshots()` and `dateDomain()` to the selected start/end dates
- Add an **X** button to dismiss the custom picker and return to the previous preset
- Chart x-axis adapts stride to the custom span (≤24h → 3h, ≤7d → 1d, longer → automatic)

## Capabilities

### New Capabilities

- `custom-date-range-picker`: Inline date range picker (start / end DatePicker + X dismiss) shown only when `timeRange == .custom`, wired to chart filtering

### Modified Capabilities

- `macos-usage-writer`: No spec-level change - implementation only touches `StatsDetailView.swift`

## Impact

- `Tempo macOS/StatsDetailView.swift` - all changes contained here
- No new files, no model changes, no iCloud or API impact
