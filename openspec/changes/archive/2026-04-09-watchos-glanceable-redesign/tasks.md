## 1. Data Layer - TokenStore & WatchSessionReceiver

- [x] 1.1 Add `usageHistory: [UsageHistorySnapshot]` property and `applyHistory(_:)` method to `TokenStore`
- [x] 1.2 Add computed `lastSession: SessionInfo?` property to `TokenStore`
- [x] 1.3 Update `WatchSessionReceiver.applyUserInfo` to decode `usageHistory` Data key and call `store.applyHistory`
- [x] 1.4 Update iOS WatchConnectivity sender to encode last 7 days of `UsageHistorySnapshot` as JSON Data in `transferUserInfo` payload

## 2. Tab Navigation Shell

- [x] 2.1 Refactor `Claude_Tracker_WatchApp` to use `TabView(.verticalPage)` with 3 pages: Dashboard, Trend, Session
- [x] 2.2 Move completion sheet `.sheet(item:)` to the TabView level so it overlays any page

## 3. Dashboard View Redesign

- [x] 3.1 Replace center countdown text with large percentage display (`.system(.title, design: .rounded)`, semibold)
- [x] 3.2 Color the percentage text to match the ring status color (green/amber/red thresholds)
- [x] 3.3 Move countdown to a secondary caption label below the ring ("Xhr Ymin" format)
- [x] 3.4 Add "Extra" pill badge below countdown when `isUsingExtraUsage` is true
- [x] 3.5 Keep mock badge and 7-day inner ring as-is (already correct)

## 4. Trend View

- [x] 4.1 Create `TrendView.swift` with 7-column bar chart using `RoundedRectangle` bars in an `HStack`
- [x] 4.2 Aggregate `usageHistory` snapshots by day, fill missing days with 0-height placeholders
- [x] 4.3 Highlight today's bar with `ClaudeCodeTheme.accent`, others with `textSecondary` at 0.6 opacity
- [x] 4.4 Add single-letter day-of-week labels (M/T/W/T/F/S/S) below each bar
- [x] 4.5 Draw dashed average reference line at mean utilization height
- [x] 4.6 Add "Avg X%" and "Peak X%" summary labels above the chart
- [x] 4.7 Add blue dot above bars for days with `isUsingExtraUsage5h == true`
- [x] 4.8 Handle empty state: show placeholder bars with "No data" caption

## 5. Session View

- [x] 5.1 Create `SessionView.swift` with last-session card (`ClaudeCodeTheme.card` background, 12pt corner radius)
- [x] 5.2 Display total tokens as primary metric (title3, rounded, abbreviated K format for > 1000)
- [x] 5.3 Display cost (USD) and duration (compact "Xm Ys") as secondary row
- [x] 5.4 Add activity status indicator: pulsing green dot if last session < 5min ago, grey "Idle" otherwise
- [x] 5.5 Add haptic alert status icon (`bell.fill` in accent)
- [x] 5.6 Add relative timestamp label ("X min ago") updating via `TimelineView`
- [x] 5.7 Handle empty state: SF Symbol + "No sessions yet" caption

## 6. Complication - WidgetKit Extension

- [x] 6.1 Create watchOS Widget Extension target in Xcode project
- [x] 6.2 Configure AppGroup capability on both watch app and widget extension targets
- [x] 6.3 Write `utilization5h` to shared AppGroup `UserDefaults` in `WatchSessionReceiver` on each update
- [x] 6.4 Call `WidgetCenter.shared.reloadAllTimelines()` after writing to AppGroup
- [x] 6.5 Implement `AccessoryCircular` gauge widget with color-coded tint and percentage center text
- [x] 6.6 Implement `TimelineProvider` with single entry and `.never` reload policy

## 7. Polish & Integration

- [x] 7.1 Verify all views use `ClaudeCodeTheme` tokens exclusively (no hardcoded colors)
- [x] 7.2 Test completion sheet presentation from each TabView page
- [x] 7.3 Test mock state badge visibility across all 3 views
- [x] 7.4 Test backward compatibility when iOS sends payload without `usageHistory` key
