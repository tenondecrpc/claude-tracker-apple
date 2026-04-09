## Why

The menu bar label currently shows only the 5-hour utilization percentage, but UsageState already contains reset countdown timers and 7-day utilization that users need to glance at frequently. Switching to the popover just to check when the rate limit resets or how the weekly window looks adds unnecessary friction for a monitoring tool.

## What Changes

- The menu bar label gains two new optional segments alongside the existing percentage:
  - **Reset countdown**: time remaining until the 5h window resets (e.g., "2:13")
  - **7-day utilization**: weekly window percentage prefixed with "7d" (e.g., "7d 18%")
- When extra usage is active (5h at 100%), the label replaces the percentage with a credits indicator (e.g., "$3.20/$20")
- Each segment is independently togglable in settings, all enabled by default
- Segments are separated by a middle dot (·) for compact readability
- Full format example: `⏺ 42% · 2:13 · 7d 18%`

## Capabilities

### New Capabilities
- `menubar-rich-label`: Configurable multi-segment menu bar label showing 5h%, reset countdown, 7d%, and extra usage credits

### Modified Capabilities
- `macos-menu-bar-ui`: Menu bar percentage text visibility requirement expands to cover multiple label segments, each with its own toggle
- `pulse-dot-icon`: Optional percentage text requirement extends to include reset countdown and 7d% segments alongside the existing percentage
- `macos-settings-preferences`: New toggle preferences for each menu bar label segment

## Impact

- **Code**: `MenuBarIconView.swift`, `MacSettingsStore.swift`, `DashboardPopoverView.swift` (or settings UI location)
- **UX**: Menu bar width increases when segments are enabled; users can disable segments they don't need
- **No new dependencies or API changes**: all data already available in `UsageState`
