## 1. Settings

- [x] 1.1 Add `showResetCountdown`, `show7dUtilization`, `showExtraUsageCredits` bools to `MacSettingsStore` with `@AppStorage`, defaulting to `true`
- [x] 1.2 Add the three new toggles to the Preferences tab under a "Menu Bar Display" group alongside the existing "Show Percentage in Menu Bar" toggle

## 2. Menu Bar Label

- [x] 2.1 Refactor `MenuBarIconView` to accept the three new settings bools and build a multi-segment label with `·` separators
- [x] 2.2 Add reset countdown segment using `TimelineView(.periodic(from:, by: 60))` displaying `H:MM` from `resetAt5h`
- [x] 2.3 Add 7-day utilization segment displaying `7d XX%` from `utilization7d`
- [x] 2.4 Add extra usage credits segment that replaces the 5h% with `$X.XX/$Y` when `isUsingExtraUsage5h` is true
- [x] 2.5 Wire new settings from `MacSettingsStore` through `ClaudeTrackerMacApp` into `MenuBarIconView`

## 3. Verification

- [x] 3.1 Build and verify all segments render correctly with mock data
- [x] 3.2 Verify each toggle independently hides its segment
- [x] 3.3 Verify countdown ticks every 60 seconds
