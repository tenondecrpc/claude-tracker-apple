# Tempo for Claude - Roadmap and Backlog

This is the single planning document for the project.

- Keep shipped work out of the active roadmap unless there is still explicit follow-up work.
- Keep `README.md` roadmap highlights aligned with the open phases below.
- Rewrite or remove stale planning notes when the implementation changes.

## Current Architecture

Tempo currently runs three connected flows:

1. **Usage pipeline** - macOS OAuth poller -> iCloud `usage.json` + `usage-history.json` -> iOS `NSMetadataQuery` -> WatchConnectivity -> watch usage surfaces and widgets.
2. **Session pipeline** - macOS `SessionEventWriter` reads completed Claude Code sessions from `~/.claude/projects/*.jsonl`, writes `latest.json` to iCloud, iOS `NSMetadataQuery` detects the file (only while app is alive), `PhoneAlertManager` schedules a local notification, and `WatchRelayManager` relays `SessionInfo` to watchOS for display in the Sessions tab.
3. **Local stats pipeline** - macOS `ClaudeLocalDBReader` reads `~/.claude/` directly for activity heatmaps, project stats, model totals, and subagent counts in the detail window.

Important constraints:

- The Anthropic OAuth API is the authoritative source for `utilization5h`, `utilization7d`, `resetAt5h`, and `resetAt7d`.
- Claude local data is the authoritative source for session history and completion detection in the current repo.
- Tempo OAuth credentials are the preferred source for usage API authentication. A fresh Claude Code CLI access token may be used as a read-only fallback, but Tempo never refreshes, writes, or deletes Claude Code credentials. See `docs/AUTH_FLOW.md`.
- Tempo does not run a custom backend today. iPhone notifications are local-only (`UNNotificationRequest` scheduled on-device) and require the iOS app to be alive in memory. There is no push infrastructure, no APNs, and no background wake mechanism. Delivery is unreliable when the app is closed.

## Completed Foundation

### Phase 1 - macOS OAuth and iCloud usage sync
**Status**: Complete

- `Tempo macOS/MacOSAPIClient.swift` handles OAuth PKCE, restore, refresh, and sign-out.
- `Tempo macOS/UsagePoller.swift` polls usage, maps `UsageState`, and writes `usage.json`.
- `Tempo macOS/UsageHistory.swift` persists and mirrors `usage-history.json`.
- `Tempo/iCloudUsageReader.swift` ingests usage and history on iOS.
- `Tempo/WatchRelayManager.swift` relays fresh usage to watchOS.

### Phase 2 - watchOS live usage
**Status**: Complete

- `Tempo Watch/WatchSessionReceiver.swift` activates `WCSession` and applies usage payloads.
- `Tempo Watch/TokenStore.swift` owns live usage and usage-history state.
- `Tempo Watch/ContentView.swift`, `Tempo Watch/TrendView.swift`, and `Tempo Watch Widget/UsageGaugeWidget.swift` surface live usage on the watch.
- `Tempo Watch/WatchRefreshCoordinator.swift` sends `RequestFreshRelay` to the iPhone on scene activation and user tap, enabling on-demand data refresh without waiting for the next passive relay cycle. The dashboard shows a refresh button with idle/in-progress/error states and a "Updated Xm ago" freshness indicator.

### Phase 3 - Session completion detection on macOS
**Status**: Complete

- The original Stop-hook plan was replaced by a shipped local-data implementation.
- `Tempo macOS/SessionEventWriter.swift` polls `~/.claude/projects/*.jsonl`, detects completed sessions, and writes `latest.json`.
- `Tempo macOS/ClaudeLocalDBReader.swift` powers richer local Claude Code stats from `~/.claude/`.

### Phase 4 - iOS session relay
**Status**: Complete (local-only, significant limitations)

- `Tempo/iCloudUsageReader.swift` watches `latest.json` via `NSMetadataQuery`.
- `Tempo/WatchRelayManager.swift` relays `SessionInfo` via `transferUserInfo(_:)`.
- `Tempo/PhoneAlertManager.swift` handles local iPhone completion notifications.

**Current notification limitations:**

The iPhone notification system is local-only and has fundamental delivery constraints:

1. **Requires the iOS app to be alive** - `NSMetadataQuery` only fires while the app process is in memory (foreground or suspended). If the user force-quits the app, or iOS reclaims memory under pressure, no session completion is detected and no notification is scheduled.
2. **No background wake mechanism** - There is no `BGTaskScheduler`, no silent push, and no background fetch configured. The app has no way to wake itself when a new `latest.json` arrives in iCloud.
3. **Latency depends on iCloud sync** - Even when the app is alive, delivery depends on iCloud Drive propagation speed, which can range from seconds to minutes depending on network conditions and Apple's sync scheduling.
4. **Not a real push notification** - Despite appearing as a banner, it is a `UNNotificationRequest` with `trigger: nil` (immediate local delivery). There is no APNs involvement, no device token, and no server-side dispatch.
5. **Watch delivery only via iOS mirror** - The watch no longer has its own notification system. Watch banners only appear if iOS notification mirroring is enabled in the Watch app settings and the iPhone notification fires while the phone is locked.

In practice, this means notifications are unreliable for the primary use case (knowing when a long-running Claude Code session finishes while away from the Mac). The user must keep the Tempo iOS app in memory for any chance of delivery. See "Desired: CloudKit Push Notifications" in the backlog section for the planned replacement.

### Phase 5 - watchOS completion alerts
**Status**: Removed

Watch-side local notifications (`WatchAlertManager`) and the in-app completion sheet (`CompletionView`) were removed. The watch still receives `SessionInfo` payloads and displays session data in the Sessions tab, but no longer presents any notification or popup overlay. The rationale: the user can see session data directly in the watch UI without interruption.

### Multi-account support
**Status**: Complete

Shipped as a clean replacement of the single-account contract. There is no migration milestone: Tempo does not read the legacy flat iCloud files (`Tempo/usage.json`, `Tempo/usage-history.json`, `Tempo/latest.json`) and does not fall back to the single-slot `credentials` Keychain entry. Developers clean up stale dev-container files manually.

Scope delivered:

- macOS `AccountRegistry` with per-account OAuth credential slots in the Keychain (service `com.tenondev.tempo.claude.oauth`, `kSecAttrAccount` = canonical accountId) plus a reserved `__registry__` slot for the non-secret account list.
- iCloud tree partitioned under `Tempo/accounts/<accountId>/` with `usage.json`, `usage-history.json`, `latest.json`, and `account.json`, plus `Tempo/accounts/index.json` as the directory index. `alert-preferences.json` and `appearance-mode.json` remain global.
- `UsagePoller` runs one `AccountPollingWorker` per account with independent 15-minute cadence and rate-limit backoff.
- `ClaudeLocalDBReader` and `SessionEventWriter` tag sessions by accountId derived from `~/.claude.json` `oauthAccount.emailAddress`; CLI-only sessions land in a dedicated `unassigned` bucket.
- iOS dashboard adds a header account chip that opens a per-account picker; dashboard and Activity views filter by the active account; `activeAccountId` persists locally, not in iCloud.
- Watch follows the iPhone's active account only: it clears state on `NoActiveAccount`, suppresses completion alerts for non-active accounts, and does not persist its own selection.
- Widgets (macOS, iOS, watchOS) render the active account by default. macOS and iOS widgets expose a `SelectAccountIntent` for pinning to a specific account.
- Shared `AccountIdentifier` canonicalizes accountIds (lowercased, trimmed, NFC-normalized email) across all targets; `UsageState`, `WidgetUsageSnapshot`, and `SessionInfo` carry `accountId`.
- Bugfix shipped: `MacOSAPIClient.tryRestoreSession()` only promotes a CLI session to `isAuthenticated = true` when the canonical CLI email matches an existing `AccountRegistry` row; `writeIndex` guards against empty-registry thrash on launch; `DashboardPopoverView` adds defense-in-depth gating so the popover is never in a mixed authenticated-but-empty-registry state.

### Already shipped UI beyond the original phase plan

- macOS detail window with Overview, Activity, and Preferences tabs.
- iOS companion Dashboard, Activity, and Settings tabs.
- iOS and macOS widget bundles backed by `WidgetUsageSnapshot`.
- watch Trend and Sessions tabs, plus an accessory circular widget.
- Light mode with Dark / Light / System appearance picker (macOS), synced via iCloud to iOS and watchOS.
- Instantaneous burn rate display on macOS popover and iOS dashboard.
- Watch on-demand refresh: refresh button in the dashboard footer, "Updated Xm ago" freshness label, and `RequestFreshRelay` message to iPhone for immediate data pull on scene activation or user tap.

## Open Roadmap

### Phase 6 - Reset alarm
**Status**: Not started

**Goal**: Fire a watch local notification and haptic at `resetAt5h`.

**Remaining work**:

- Add a watch-side scheduler that reschedules whenever `UsageState.resetAt5h` changes.
- Define notification copy and behavior when the reset time moves or the app is offline.
- Validate on device that the alarm survives backgrounding, reconnects, and app relaunches.

### Phase 7 - QA and reliability hardening
**Status**: In progress

**Goal**: Close the gap between "implemented" and "release-verified".

**Remaining work**:

- Run and document end-to-end device verification for macOS -> iPhone -> watch usage sync.
- Verify session completion latency and duplicate suppression across reconnects and app restarts.
- Confirm notification-permission behavior on iPhone and watchOS, including disabled-permission states.
- Keep `tools/widget_smoke_test.swift` current for widget snapshot and route changes.

### Phase 8 - Deeper stats surfaces and richer watch complications
**Status**: Partially complete

**Already shipped**:

- macOS local Claude Code stats and activity heatmap via `ClaudeLocalDBReader`.
- iOS Activity charts from `usage-history.json`.
- watch Trend tab and accessory circular usage widget.

**Remaining work**:

- Decide whether to expose per-session local Claude history on iOS and/or watch, not just aggregated usage history.
- Expand watch complications/widgets beyond the current circular utilization surface, ideally adding reset countdown or more families.
- Decide whether project and model stats should remain macOS-only or be shared with companion surfaces.

### Phase 9 - Context window tracking
**Status**: Not started

**Goal**: Show active context-window fullness and threshold alerts.

**Current gap**:

- The repo has no `ContextState` model or transport path today.
- The data source for reliable context-window metrics still needs confirmation in the current Claude Code integration.

**Remaining work**:

- Confirm a stable data source for live context usage.
- Add a shared model plus transport path to iOS and watchOS.
- Design threshold-crossing alerts that avoid repeated notifications.

## Out Of Scope For Current Phases

- Cross-platform transport replacement for iCloud, if Tempo ever targets Windows or non-Apple sync paths.

## Security Hardening

All findings from the 2026-05-03 security audit (items #1-#9) are implemented. The completed OpenSpec change is archived under `openspec/changes/archive/`.

## Unscheduled Backlog

1. **Historical pace prediction** - Forecast session and weekly usage based on burn rate and historical behavior. The instantaneous burn rate (%/hr, shown in the macOS popover and iOS dashboard) is already shipped; this item covers trend-line extrapolation and weekly forecasts from `usage-history.json`.
2. **Live session chart** - Show real-time, sub-30-second chart updates during an active session.
3. **Time-of-day breakdowns** - Add hourly and time-of-day breakdowns alongside the existing day-level views (watch 7-day bar chart, macOS activity heatmap).
4. **Bar chart alternatives on iOS/macOS** - Offer `BarMark`-based chart alternatives to the current line/area charts. A custom bar chart already exists on watchOS (`TrendView`).
5. **Consumption rate histogram** - Show how often usage falls into utilization bands such as 0-25% or 25-50%.
6. **Scheduled triggers / automations** - Add configurable automation rules such as "alert me at 80%" or Shortcuts integration.
7. **Codex / Claude API key support** - Support usage tracking for users working through raw API keys instead of OAuth.
8. **All Accounts dashboard** - Aggregate usage across multiple Claude accounts or workspaces in a single combined view. Multi-account support is shipped; this item covers the cross-account aggregation surface that was intentionally left out of scope (no "combined usage" views ship with multi-account).
9. **Per-account display-name editing** - Allow users to rename an account's display label (accountId itself remains immutable). Surfaced as a future enhancement in the multi-account design.
10. **CloudKit push notifications for session completion** - Replace the current local-only notification system with CloudKit subscriptions to deliver real push notifications to iPhone (and by mirror, to Apple Watch) even when the iOS app is fully closed. See "Desired: CloudKit Push Notifications" section below for full design rationale.

## Desired: CloudKit Push Notifications

### Problem

The current notification system relies on `NSMetadataQuery` in the iOS app to detect new session files in iCloud Drive. This only works while the app process is alive (foreground or suspended in memory). If the user kills the app or iOS reclaims memory, no notification is delivered.

### Proposed Solution: CloudKit Subscriptions

Use CloudKit's private database with `CKQuerySubscription` to receive silent push notifications when the macOS app writes a session completion record. This wakes the iOS app in the background to schedule a local `UNNotificationRequest` that the user sees as a real push.

### Why CloudKit

1. **No custom backend required** - CloudKit is Apple infrastructure. No servers to maintain, no uptime to monitor, no deployment pipeline.
2. **Zero cost for private database** - Data stored in the user's private CloudKit database counts against their personal iCloud storage quota (5 GB free tier or whatever plan they have). Apple never bills the developer for private database usage.
3. **Privacy by design** - Private database records are encrypted and accessible only by the authenticated Apple ID owner. The developer cannot read them from the CloudKit Dashboard. No third-party access, no data sharing. Same privacy guarantees as iCloud Drive today.
4. **Native push delivery** - `CKSubscription` triggers a silent push via APNs without needing device token management, a push server, or APNs certificates for the developer to rotate.
5. **Works with app closed** - Unlike `NSMetadataQuery`, CloudKit silent pushes wake the app via `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` even when the process is terminated.

### Architecture

```
macOS app detects session completion
    |
    v
Writes CKRecord (type: "SessionCompletion") to CloudKit private DB
    |
    v
CloudKit fires CKQuerySubscription push to iPhone
    |
    v
iOS app wakes in background (didReceiveRemoteNotification)
    |
    v
Reads the CKRecord, schedules local UNNotificationRequest
    |
    v
iOS delivers notification banner (mirrors to watch if enabled in iOS Settings)
```

### Implementation Notes

- The macOS app already has iCloud entitlements. Adding CloudKit container access is a capability toggle in Xcode.
- The iOS app registers a `CKQuerySubscription` on first launch for record type `SessionCompletion` in the private database.
- Silent pushes are best-effort (iOS may throttle them in Low Power Mode or under heavy system load), but delivery reliability is significantly better than the current `NSMetadataQuery` approach which requires the app to be alive.
- The existing iCloud Drive sync for `usage.json` and `usage-history.json` remains unchanged. CloudKit is only used for the session completion push trigger.
- Watch notifications come for free via iOS notification mirroring - no watch-specific code needed.

### Limitations

- Silent pushes are not 100% guaranteed by iOS. Under extreme conditions (Low Power Mode, heavy background activity) they may be delayed or dropped.
- Requires the user to be signed into iCloud on both macOS and iOS with the same Apple ID (already a requirement for the current iCloud Drive sync).
- First-time setup requires the iOS app to register the subscription, which means the app must be launched at least once after install.
