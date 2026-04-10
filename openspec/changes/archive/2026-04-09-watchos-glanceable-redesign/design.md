## Context

The watchOS app currently renders a single `ContentView` with concentric utilization rings (5h outer, 7d inner) and a text countdown. Data arrives via `WatchConnectivity.transferUserInfo` from the iOS companion, which relays `UsageState` from iCloud. The watch has no history data, no complications, and no multi-view navigation.

The `ClaudeCodeTheme` token system is already adopted across all watch views. `UsageHistorySnapshot` exists in `Shared/UsageHistoryModels.swift` and is used by macOS/iOS for charting — we need to bring these snapshots to the watch.

**Current watch files:**
- `Claude_Tracker_WatchApp.swift` — entry point, creates `TokenStore` + `WatchSessionReceiver`
- `ContentView.swift` — single ring view with countdown
- `CompletionView.swift` — session-done sheet
- `TokenStore.swift` — observable store with `UsageState` + `pendingCompletion`
- `WatchSessionReceiver.swift` — `WCSessionDelegate` parsing `transferUserInfo`

## Goals / Non-Goals

**Goals:**
- 3 focused views navigable via vertical Digital Crown paging (Apple HIG pattern for watchOS)
- Graphic-first dashboard with large percentage readout and status color coding
- 7-day trend visualization using native SwiftUI shapes (no Charts framework dependency)
- Last-session summary card with activity status
- WidgetKit accessory complication showing 5h utilization gauge
- Extend `transferUserInfo` payload to deliver history snapshots to the watch

**Non-Goals:**
- Interactive session management (start/stop) from the watch
- Push notifications from the watch (handled by iOS)
- Custom watch faces or rich complications beyond circular gauge
- Fetching data directly from Anthropic API on the watch (battery/connectivity constraints)
- Charting frameworks (Swift Charts requires watchOS 10+ and adds bundle size — use custom SwiftUI shapes)

## Decisions

### 1. Navigation: Vertical-page TabView

**Choice:** `TabView` with `.tabViewStyle(.verticalPage)` (watchOS 10+)

**Why over NavigationStack:** watchOS HIG recommends vertical paging for "peer" content that users glance at sequentially. NavigationStack is better for hierarchical drill-down, which doesn't match our "3 dashboards" model. Digital Crown maps naturally to page scrolling.

**Alternative considered:** `.carousel` style — rejected because it's deprecated in watchOS 10 in favor of `.verticalPage`.

### 2. Trend chart: Custom SwiftUI bar shapes

**Choice:** Hand-drawn `RoundedRectangle` bars in an `HStack` with proportional heights.

**Why over Swift Charts:** Swift Charts is only available on watchOS 10+ and adds binary size. Our chart is simple (7 bars, one reference line) — custom shapes give full control over sizing on the small screen and keep the widget extension lightweight.

### 3. History data delivery: Extend existing `transferUserInfo`

**Choice:** Add an `usageHistory` key to the existing `UsageState` `transferUserInfo` payload, encoding `[UsageHistorySnapshot]` as a JSON data blob within the dictionary.

**Why not a separate transfer:** `transferUserInfo` queues are FIFO and coalesced. Sending history in the same payload as usage ensures atomicity — the watch always has matching current + history state. A separate `transferUserInfo` call could arrive out of order or be coalesced away.

**Encoding:** `usageHistory` → `Data` via `JSONEncoder`, stored as `Data` value in `userInfo` dictionary. `WatchSessionReceiver` decodes it back to `[UsageHistorySnapshot]`.

### 4. TokenStore expansion

**Choice:** Add `usageHistory: [UsageHistorySnapshot]` and `lastSession: SessionInfo?` properties to the existing `TokenStore`.

`lastSession` is derived from the most recent entry in `sessions` array (already exists but unused on watch). History snapshots are stored in-memory only — no persistence needed since the iOS companion resends on each update.

### 5. Complication: WidgetKit AccessoryCircular

**Choice:** New watchOS Widget Extension target using `AccessoryCircularGaugeStyle` with `Gauge` view.

**Why WidgetKit over ClockKit:** ClockKit is deprecated. WidgetKit accessory widgets are the modern API and work across all watch faces. `AccessoryCircular` is the most universal complication family.

**Data sharing:** The widget reads from a shared `AppGroup` `UserDefaults` where `WatchSessionReceiver` writes the latest `utilization5h` value. This avoids the widget needing its own WCSession.

### 6. Dashboard redesign: Percentage-centric layout

**Choice:** Large `.system(.title, design: .rounded)` percentage text in the ring center, replacing the countdown text. Countdown moves below the ring as a smaller caption. A thin color band at the top indicates status (green/yellow/red). Plan tier and extra-usage badge shown as small pills.

**Why:** Apple HIG says the most important information should be the largest element. Percentage is the primary glanceable metric; countdown is secondary context.

## Risks / Trade-offs

**[watchOS version requirement]** → `TabView(.verticalPage)` requires watchOS 10+. The current deployment target should already be watchOS 10. If not, bump it — watchOS 9 adoption is negligible.

**[History payload size]** → 30 days of snapshots (~30 entries × ~100 bytes = ~3KB) is well within `transferUserInfo` limits (no documented cap, but practically safe under 1MB). We only send last 7 days to keep it lean.

**[Widget refresh frequency]** → WidgetKit on watchOS has a limited timeline budget. The widget shows a static gauge that refreshes when the app writes new data to `AppGroup`. During long idle periods the gauge may show stale data — acceptable since the user can tap to open the app.

**[App Group provisioning]** → The complication requires an `AppGroup` shared between the watch app and widget extension. This needs to be configured in Xcode Signing & Capabilities for both targets.
