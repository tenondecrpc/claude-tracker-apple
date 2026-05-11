## Context

The watch app receives usage data exclusively via WatchConnectivity. The iPhone's `AppCoordinator` wires `iCloudUsageReader.onUsageState` to `WatchRelayManager.send(_:)`, which calls `updateApplicationContext` (replace-current-state) or falls back to `transferUserInfo`. The watch's `WatchSessionReceiver` picks up the payload and applies it to `TokenStore`.

Today, the watch has no way to request fresh data. It passively waits for the iPhone to push. If the iPhone app is backgrounded or the iCloud file hasn't changed since the last push, the watch shows stale data indefinitely.

WatchConnectivity's `sendMessage(_:replyHandler:errorHandler:)` is the standard mechanism for watch-initiated requests. It requires the counterpart app to be reachable (Bluetooth/WiFi range, iPhone not in airplane mode). On iOS, receiving a `sendMessage` from the watch wakes the iOS app briefly if it's suspended, which is sufficient for our use case.

## Goals / Non-Goals

**Goals:**
- Watch SHALL be able to request fresh usage data from the iPhone on scene activation and on user tap.
- iPhone SHALL respond by re-reading iCloud and re-relaying the active account's `UsageState` via the existing relay path.
- Watch SHALL show a visible refresh control with idle/in-progress/error states.
- Watch SHALL show a "Updated Xm ago" freshness indicator.
- The mechanism SHALL degrade gracefully when the iPhone is not reachable (error state, not crash).

**Non-Goals:**
- Not adding iCloud access to the watch target. watchOS does not reliably support ubiquity containers for third-party apps.
- Not adding background refresh or complications-driven triggers on the watch.
- Not changing the macOS writer or the iCloud file format.
- Not adding a periodic timer on the watch. Refresh fires only on scene activation and user tap.
- Not changing `SessionInfo` delivery. Completion events remain `transferUserInfo`-only.

## Decisions

**Decision 1: `sendMessage` for the request, `updateApplicationContext` for the response.**
The watch sends a lightweight `sendMessage` with `["type": "RequestFreshRelay"]`. The iPhone does NOT reply with the usage data in the `replyHandler`; instead it triggers its normal relay path (`WatchRelayManager.send(_:)` which calls `updateApplicationContext`). Rationale: the relay path already handles history, alert preferences, appearance mode, and account label bundling. Duplicating that in a reply handler would create a second serialization path. The reply handler just acknowledges receipt with `["ok": true]`. Alternative considered: reply with full payload. Rejected because it bypasses the existing relay infrastructure and its coalescing/fallback logic.

**Decision 2: iPhone restarts iCloudUsageReader on request.**
When the iPhone receives `RequestFreshRelay`, it calls `iCloudUsageReader.restart()` which stops and re-starts the `NSMetadataQuery`. This picks up any iCloud changes that occurred while the iOS app was backgrounded. After the query fires, the existing `onUsageState` callback triggers `relay.send(_:)` naturally. If the file hasn't changed, the query fires with the same data and the relay sends the same state (which is fine; the watch just sees "Updated just now"). Alternative considered: only re-send the cached state without restarting the reader. Rejected because the whole point is to get fresh data from iCloud, not replay stale cache.

**Decision 3: Watch refresh coordinator tracks success by observing `TokenStore` timestamp.**
The coordinator transitions from `.inProgress` to `.idle` when `TokenStore.lastRelayReceivedAt` updates after the request was sent. It does NOT rely on the `sendMessage` reply alone (the reply only confirms the iPhone received the request, not that it has fresh data to send). A timeout of 10 seconds transitions to `.error` if no new relay arrives. Alternative considered: use the reply handler as the success signal. Rejected because the reply fires before the iCloud read completes; the watch would show "success" before data actually arrives.

**Decision 4: Refresh button in a bottom footer row, not floating overlay.**
Prior iteration showed that a floating top-trailing icon clips against watchOS rounded corners on smaller devices. A centered bottom footer avoids this entirely and matches the pattern used by comparable watch apps. The button is always visible but disabled when no `activeAccountId` is known.

**Decision 5: No source-precedence logic needed.**
Unlike the prior iCloud-direct approach, there is only one source of `UsageState` on the watch: WatchConnectivity from the iPhone. The refresh mechanism just accelerates when that source delivers. No timestamp comparison or source tagging is needed in `TokenStore`.

**Decision 6: `session.isReachable` gate before sending.**
The coordinator checks `WCSession.default.isReachable` before calling `sendMessage`. If not reachable, it immediately transitions to `.error("iPhone not reachable")` without attempting the send. This avoids a ~30s timeout that `sendMessage` would otherwise impose before calling the error handler.

## Risks / Trade-offs

- **iPhone must be reachable** - If the iPhone is off, in airplane mode, or out of Bluetooth/WiFi range, the refresh fails with a clear error message. This is an inherent limitation of WatchConnectivity `sendMessage`. Mitigation: clear error state with retry affordance.
- **iOS app must be able to wake** - `sendMessage` wakes a suspended iOS app, but if the user has force-killed the iOS app from the app switcher, the message will fail. Mitigation: error message suggests "Open Tempo on iPhone".
- **iCloud read latency** - The iPhone's `iCloudUsageReader.restart()` may take 1-3 seconds to fire the metadata query and decode the file. The watch shows a spinner during this time. Mitigation: 10s timeout prevents indefinite spinner.
- **Redundant relay when data hasn't changed** - If the user taps refresh but iCloud hasn't been updated by macOS, the iPhone re-sends the same `UsageState`. The watch updates "Updated just now" which is technically correct (the relay is fresh, even if the underlying data is the same). This is acceptable UX.
