## Why

Phase 1 built the iOS side of the data pipeline — OAuth sign-in, polling, and `transferUserInfo` delivery. The watch currently has no receiver: `WCSession` is never activated on watchOS and `TokenStore` has no way to accept incoming data. This change completes Track A by wiring up the watch end so the usage ring shows real utilization and the mock badge disappears.

## What Changes

- **New** `WatchSessionReceiver.swift` (Watch Extension) — `WCSessionDelegate` that activates `WCSession`, receives `transferUserInfo` payloads, decodes the `"type"` discriminator, and routes `UsageState` payloads to `TokenStore`
- **Modified** `TokenStore.swift` — add `func apply(_ state: UsageState)` that sets `usageState` and is called by the receiver
- **Modified** `Claude_Tracker_WatchApp.swift` — instantiate `WatchSessionReceiver` at launch, inject `TokenStore` into the view hierarchy

## Capabilities

### New Capabilities

- `watch-session-receiver`: WCSession activation on watchOS, payload routing by type discriminator, thread-safe `@MainActor` delivery

### Modified Capabilities

- `token-store`: gains `apply(_ state: UsageState)` — a method that accepts incoming real data and clears the mock flag
- `watch-dashboard`: no code changes; the mock badge disappears automatically when `TokenStore.usageState.isMocked` becomes `false`

## Impact

- **New file**: `ClaudeTracker Watch Extension/WatchSessionReceiver.swift`
- **Modified**: `ClaudeTracker Watch Extension/TokenStore.swift` (+1 method)
- **Modified**: `ClaudeTracker Watch/Claude_Tracker_WatchApp.swift` (wiring)
- Watch Extension target only — no changes to iOS target or Shared
