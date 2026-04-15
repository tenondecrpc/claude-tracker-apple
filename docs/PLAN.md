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

### Already shipped UI beyond the original phase plan

- macOS detail window with Overview, Activity, and Preferences tabs.
- iOS companion Dashboard, Activity, and Settings tabs.
- iOS and macOS widget bundles backed by `WidgetUsageSnapshot`.
- watch Trend and Sessions tabs, plus an accessory circular widget.

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

## Unscheduled Backlog

1. **Multi-account support** - Add and switch between multiple Claude accounts within one app instance.
2. **Light mode** - Support a full light-theme variant instead of dark-mode-only UI.
3. **Pace prediction** - Forecast session and weekly usage based on burn rate and historical behavior.
4. **Live session chart** - Show real-time, sub-30-second chart updates during an active session.
5. **Day/week usage breakdowns** - Add weekday and time-of-day breakdowns, heatmaps, or similar granular views.
6. **Bar charts** - Offer bar-chart alternatives alongside the current line/area visualizations.
7. **Consumption rate histogram** - Show how often usage falls into utilization bands such as 0-25% or 25-50%.
8. **Scheduled triggers / automations** - Add configurable automation rules such as "alert me at 80%" or Shortcuts integration.
9. **Codex / Claude API key support** - Support usage tracking for users working through raw API keys instead of OAuth.
10. **All Accounts dashboard** - Aggregate usage across multiple Claude accounts or workspaces.
11. **Dedicated-server push notifications for Claude Code replies** - Detect Claude Code reply completion on macOS and send the event to a dedicated push server that owns device registration, APNs credentials, and delivery to iPhone and watch. Keep this as a future backlog item, not part of the current committed phases.
