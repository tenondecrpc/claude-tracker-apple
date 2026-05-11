## Why

The watch app shows stale data when the iPhone hasn't recently pushed a WatchConnectivity update. Users open the watch expecting fresh usage and see whatever was last relayed, with no way to force a refresh. A prior attempt to read iCloud Drive directly from watchOS failed because `url(forUbiquityContainerIdentifier:)` returns nil for third-party apps on watchOS (the ubiquity container is not provisioned on the watch regardless of entitlements).

This change adds a lightweight request-reply mechanism: the watch asks the iPhone for fresh data via `sendMessage`, the iPhone re-reads iCloud and relays the latest `UsageState` back. The watch gets a visible refresh control and a freshness indicator so the user knows when data was last updated and can trigger a refresh on demand.

## What Changes

- Watch sends a `RequestFreshRelay` message to the iPhone on scene activation (foreground) and on user tap of a new refresh button.
- iPhone receives the message, restarts its `iCloudUsageReader`, and immediately re-sends the active account's `UsageState` via the existing `WatchRelayManager.send(_:)` path.
- Watch dashboard gains a refresh icon button (bottom footer, centered) with three visual states: idle, in-progress, error.
- Watch dashboard gains a "Updated Xm ago" freshness indicator inside the ring.
- No new entitlements. No iCloud access on the watch. No changes to macOS.

## Capabilities

### New Capabilities
- `watch-refresh-request`: Watch-side coordinator that sends `RequestFreshRelay` messages to the iPhone and tracks the refresh lifecycle (idle/in-progress/error/success).
- `watch-refresh-ui`: Dashboard refresh button and freshness indicator UI components.

### Modified Capabilities
- `watch-relay`: iPhone's `WatchRelayManager` gains a `didReceiveMessage` handler for `RequestFreshRelay` that triggers an immediate re-relay of the active account's usage state.
- `watch-dashboard`: Dashboard hosts the refresh button footer and freshness indicator.

## Impact

- **Code (watch)**: New `WatchRefreshCoordinator.swift`, changes to `Tempo_WatchApp.swift` (scene wiring), changes to `ContentView.swift` (refresh button + freshness label).
- **Code (iOS)**: Changes to `WatchRelayManager.swift` (new `didReceiveMessage` handler), changes to `TempoApp.swift` (wire the callback from relay to iCloud reader restart + re-send).
- **Entitlements**: None. No new capabilities needed.
- **macOS**: No changes.
- **Risk**: Low. Uses existing WatchConnectivity infrastructure. Only new behavior is the watch-initiated message and the iPhone's response to it.
