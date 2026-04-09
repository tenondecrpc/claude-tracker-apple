## Context

The macOS menu bar currently displays a pulse dot icon with an optional single percentage (`utilization5h`). The `UsageState` model already carries `resetAt5h`, `utilization7d`, `resetAt7d`, and `extraUsage` — all unused in the label. Users must open the popover to see reset timing or weekly utilization, which defeats the purpose of a glanceable monitor.

## Goals / Non-Goals

**Goals:**
- Show reset countdown, 7-day utilization, and extra usage credits in the menu bar label
- Let users toggle each segment independently via preferences
- Keep the label compact and readable at small font sizes

**Non-Goals:**
- Changing the pulse dot icon rendering itself
- Adding color to menu bar text (not possible with template-mode `MenuBarExtra`)
- Showing `resetAt7d` countdown (too long to be useful in a label)

## Decisions

### 1. Label segments as composable `Text` views in an HStack

Build each segment as a separate computed property returning optional `Text`. The `body` filters non-nil segments and joins them with ` · ` separators. This keeps the view declarative and each segment independently testable.

**Alternative considered**: Single formatted string — harder to toggle individual segments and loses type safety.

### 2. Reset countdown uses a `TimelineView` for live updates

The countdown needs to tick every minute. A `TimelineView(.periodic(from:, by: 60))` drives the label so it stays current without a manual timer. When `resetAt5h` is in the past, the segment shows "0:00".

**Alternative considered**: `Timer.publish` — works but `TimelineView` is the idiomatic SwiftUI approach and handles view lifecycle automatically.

### 3. Settings stored as individual `@AppStorage` bools in `MacSettingsStore`

Three new bools: `showResetCountdown`, `show7dUtilization`, `showExtraUsageCredits` — all defaulting to `true`. Follows the existing pattern used by `showPercentageInMenuBar`.

### 4. Extra usage segment replaces percentage when 5h is at 100%

When `isUsingExtraUsage5h` is true, the 5h% segment switches from "100%" to "$X.XX/$Y" to show credit burn. This avoids a stale "100%" sitting in the label when the user is actively spending credits.

### 5. Segment separator is ` · ` (spaced middle dot)

Compact, visually neutral, and renders well in both light and dark menu bars as template text.

## Risks / Trade-offs

- **Menu bar width**: With all segments enabled the label could reach ~20 characters. Users with many menu bar items may need to disable segments. → Mitigation: each segment is toggleable; disabled by default would reduce discoverability so we default all on.
- **Countdown flicker**: `TimelineView` redraws every 60s which is fine, but if the poller updates mid-minute the countdown could jump. → Mitigation: countdown is derived from `resetAt5h` (absolute time), not from poller ticks, so it's always correct.
