# Tempo for Claude - Roadmap and Backlog

This is the single planning document for the project.

- Keep shipped work out of the active roadmap unless there is still explicit follow-up work.
- Keep `README.md` roadmap highlights aligned with the open phases below.
- Rewrite or remove stale planning notes when the implementation changes.

## Current Architecture

Tempo currently runs three connected flows:

1. **Usage pipeline** - macOS OAuth poller -> iCloud `usage.json` + `usage-history.json` -> iOS `NSMetadataQuery` -> WatchConnectivity -> watch usage surfaces and widgets.
2. **Session pipeline** - macOS `SessionEventWriter` reads completed Claude Code sessions from `~/.claude/projects/*.jsonl`, writes `latest.json`, iOS relays `SessionInfo`, and iPhone/watchOS present local completion notifications.
3. **Local stats pipeline** - macOS `ClaudeLocalDBReader` reads `~/.claude/` directly for activity heatmaps, project stats, model totals, and subagent counts in the detail window.

Important constraints:

- The Anthropic OAuth API is the authoritative source for `utilization5h`, `utilization7d`, `resetAt5h`, and `resetAt7d`.
- Claude local data is the authoritative source for session history and completion detection in the current repo.
- Tempo OAuth credentials are the preferred source for usage API authentication. A fresh Claude Code CLI access token may be used as a read-only fallback, but Tempo never refreshes, writes, or deletes Claude Code credentials. See `docs/AUTH_FLOW.md`.
- Tempo does not run a custom backend today. Alerts are local and depend on iCloud sync plus the iPhone/watch relay.

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
**Status**: Complete

- `Tempo/iCloudUsageReader.swift` watches `latest.json`.
- `Tempo/WatchRelayManager.swift` relays `SessionInfo` via `transferUserInfo(_:)`.
- `Tempo/PhoneAlertManager.swift` handles local iPhone completion notifications.

### Phase 5 - watchOS completion alerts
**Status**: Complete

- `Tempo Watch/WatchSessionReceiver.swift` routes `SessionInfo`.
- `Tempo Watch/WatchAlertManager.swift` schedules local watch notifications.
- `Tempo Watch/CompletionView.swift` presents completed-session details.

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
- Dedicated server push delivery for session completion. Current notifications remain local-only.

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
10. **Dedicated-server push notifications for Claude Code replies** - Detect Claude Code reply completion on macOS and send the event to a dedicated push server that owns device registration, APNs credentials, and delivery to iPhone and watch. Keep this as a future backlog item, not part of the current committed phases.
