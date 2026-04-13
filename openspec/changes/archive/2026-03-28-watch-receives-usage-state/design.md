## Context

Phase 1 built the full iOS pipeline: OAuth sign-in → 15-minute polling → `WatchRelayManager.send(_:)` calls `transferUserInfo`. The watch extension has `TokenStore` with `usageState: UsageState = .mock` and a `WatchDashboard` that correctly reads it - but `WCSession` is never activated on watchOS, so the payloads are never received. This change is the final wire.

Current state:
- `TokenStore.usageState` is always `.mock` (hard-coded initializer)
- `Claude_Tracker_WatchApp` has no WCSession setup
- `WatchDashboard` already correctly renders `isMocked` badge - it disappears automatically when `isMocked` flips to `false`

## Goals / Non-Goals

**Goals:**
- Activate `WCSession` on the watch extension at launch
- Receive `transferUserInfo` payloads and route `UsageState` type to `TokenStore`
- `TokenStore.apply(_:)` sets `usageState` and clears the mock flag
- Ring shows real utilization on first payload; mock badge disappears

**Non-Goals:**
- Two-way communication (watch → iOS) - relay is iOS-only
- Queued payload replay or persistence across watch app restarts
- Session list updates via WatchConnectivity (still iCloud-driven)

## Decisions

### D1: WatchSessionReceiver as a separate class (not embedded in TokenStore)

`TokenStore` is a pure data store. Embedding `WCSessionDelegate` in it would give it a WatchConnectivity concern. A separate `WatchSessionReceiver` receives payloads and calls `store.apply(_:)` - clean separation.

Alternative: subclass or extend `TokenStore` to conform to `WCSessionDelegate`. Rejected: mixes networking and state concerns in one type.

### D2: WatchSessionReceiver holds a strong reference to TokenStore

The receiver must call `store.apply(_:)` from `didReceiveUserInfo`. It holds `let store: TokenStore`. The app entry point holds the receiver for its lifetime - no retain-cycle risk since nothing points back up.

### D3: @MainActor dispatch in didReceiveUserInfo

`WCSessionDelegate.session(_:didReceiveUserInfo:)` is called on a background thread. `TokenStore` is `@MainActor`. The receiver dispatches via `Task { @MainActor in store.apply(payload) }` - clean async hop, no DispatchQueue.main.async.

Alternative: make `WatchSessionReceiver` itself `@MainActor`. Rejected: `WCSessionDelegate` methods are called from non-main threads and Swift concurrency will warn about the mismatch unless the hop is explicit.

### D4: Type discriminator check ("type" == "UsageState")

The `transferUserInfo` protocol uses a `"type"` key to discriminate payload kinds (established in Phase 1 `WatchRelayManager`). The receiver checks this key and ignores unknown types - forward-compatible as new payload types are added.

### D5: TokenStore.usageState setter remains private(set)

`apply(_:)` is the only mutation path. `private(set)` prevents views from accidentally writing the property while still allowing the store to update it from the receiver.

## Risks / Trade-offs

- **WCSession not reachable at launch** → `WCSession.isSupported()` guard prevents crash; receiver activates anyway so it's ready when reachability is established
- **Payload arrives while app is suspended** → `transferUserInfo` guarantees delivery when app next launches; `didReceiveUserInfo` will fire and update the store
- **Type key missing in payload** → receiver silently ignores; no crash, state stays as last known value

## Open Questions

None - the implementation is fully specified.
