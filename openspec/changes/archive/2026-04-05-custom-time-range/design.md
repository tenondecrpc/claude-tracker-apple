## Context

`StatsDetailView` already has `TimeRange.custom` in its enum with a fallback that returns all snapshots. The chart header is an `HStack` with a `Menu` picker on the trailing edge. No new models or files are needed - this is a pure UI change within `StatsDetailView.swift`.

## Goals / Non-Goals

**Goals:**
- Show `DatePicker` (start + end) inline in the chart header when `.custom` is selected
- Filter chart data to the selected date range
- X button returns user to the previous preset range
- X-axis stride adapts to the custom span

**Non-Goals:**
- Persisting the custom range across app launches
- Validation beyond ensuring start ≤ end
- Time-of-day precision (date granularity only)

## Decisions

**D1 - Inline pickers, not a sheet**
Inline keeps the interaction fast and matches the reference screenshot. A sheet would add unnecessary modal overhead for a two-field form.

**D2 - `previousTimeRange` state to restore on dismiss**
Capturing the range before switching to `.custom` lets the X button restore it without a separate "last non-custom" sentinel value in the enum.

**D3 - DatePicker `.graphical` style vs `.compact`**
Use `.compact` (stepper-style) - matches the screenshot and stays small inside the `HStack`. `.graphical` would expand the layout.

**D4 - X-axis stride for custom ranges**
Compute stride from the span: ≤2h → 30min, ≤24h → 3h, ≤7d → 1d, otherwise → `.automatic`. Avoids illegible label crowding.

## Risks / Trade-offs

- [start > end selection] User could pick an inverted range → Mitigation: clamp `customEnd` to always be ≥ `customStart` via `onChange`
- [Label width] "Custom" label in the menu button is the same width as preset labels - the `DatePicker` row expands the header HStack → no issue, `Spacer()` handles it
