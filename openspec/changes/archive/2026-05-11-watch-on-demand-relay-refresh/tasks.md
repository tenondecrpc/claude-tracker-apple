## 1. TokenStore freshness tracking

- [x] 1.1 Add `lastRelayReceivedAt: Date?` property to `TokenStore` that records when the most recent `UsageState` was applied (set in `apply(_:)`)
- [x] 1.2 Add a computed `lastRelayReceivedAtForActiveAccount: Date?` that returns `lastRelayReceivedAt` only when `activeAccountId` is non-nil and not in `hasNoActiveAccount` state

## 2. iPhone: WatchRelayManager receives RequestFreshRelay

- [x] 2.1 Add `session(_:didReceiveMessage:replyHandler:)` to `WatchRelayManager`'s `WCSessionDelegate` extension
- [x] 2.2 In the handler, check for `["type": "RequestFreshRelay"]`; reply `["ok": true]` and call `onFreshRelayRequested?()` callback
- [x] 2.3 For unknown or missing type, reply `["ok": false, "reason": "..."]` without calling any callback
- [x] 2.4 Add `var onFreshRelayRequested: (() -> Void)?` property to `WatchRelayManager`

## 3. iPhone: AppCoordinator wires the callback

- [x] 3.1 In `AppCoordinator.init()`, set `relay.onFreshRelayRequested` to a closure that calls `iCloudUsageReader.restart()` and then re-sends the active account's usage state via the existing relay path
- [x] 3.2 If no active account or no cached usage, call `relay.sendNoActiveAccount()` instead
- [x] 3.3 Add a `DevLog.trace("AlertTrace", ...)` line when the fresh relay request is received and when the re-send fires

## 4. Watch: WatchRefreshCoordinator

- [x] 4.1 Create `Tempo Watch/WatchRefreshCoordinator.swift` as `@MainActor`, `@Observable` with `state: RefreshControlState` enum (`.idle`, `.inProgress`, `.error(reason: String)`)
- [x] 4.2 Implement `requestRefresh()`: check `isReachable`, send `["type": "RequestFreshRelay"]` via `WCSession.default.sendMessage`, transition to `.inProgress`
- [x] 4.3 On `sendMessage` error handler, transition to `.error` with user-friendly reason
- [x] 4.4 Implement success detection: observe `TokenStore.lastRelayReceivedAt` changes; if it updates after the request was sent, transition to `.idle`
- [x] 4.5 Implement 10-second timeout: if no fresh relay arrives within 10s, transition to `.error("No response from iPhone")`
- [x] 4.6 Single-flight guard: if `state == .inProgress`, `requestRefresh()` returns immediately

## 5. Watch: Scene wiring

- [x] 5.1 Add `refreshCoordinator` to `WatchAppCoordinator`, pass `store` reference to it
- [x] 5.2 Inject `refreshCoordinator` into the SwiftUI environment alongside `store`
- [x] 5.3 In `onScenePhaseChange(.active)`, call `refreshCoordinator.requestRefresh()` when `store.activeAccountId` is non-nil and `hasNoActiveAccount` is false
- [x] 5.4 Do NOT call `requestRefresh()` when no active account; add comment referencing spec scenario

## 6. Watch: Dashboard UI

- [x] 6.1 Add refresh button footer below the ring in `ContentView.swift` (centered HStack with the refresh icon button)
- [x] 6.2 Render three visual states: idle (static icon), in-progress (rotating symbol effect), error (red dot badge)
- [x] 6.3 Disable button when `activeAccountId == nil` or `hasNoActiveAccount`
- [x] 6.4 On tap while `.idle` or `.inProgress`: call `requestRefresh()` (single-flight handles dedup)
- [x] 6.5 On tap while `.error`: show alert with reason, then retry
- [x] 6.6 Add "Updated Xm ago" label inside ring center VStack, below "5H", using `RelativeDateTimeFormatter`
- [x] 6.7 Add `.accessibilityLabel("Refresh usage")` and `.accessibilityValue(...)` to the button

## 7. Build and verification

- [x] 7.1 Build `Tempo Watch` scheme and confirm no compile errors
- [x] 7.2 Build `Tempo` (iOS) scheme and confirm no compile errors from the relay changes
- [x] 7.3 Manual device test: open watch app with iPhone running, confirm refresh fires on activation and ring updates
- [x] 7.4 Manual device test: tap refresh button, confirm spinner then success
- [x] 7.5 Manual device test: put iPhone in airplane mode, tap refresh, confirm "iPhone not reachable" error
- [x] 7.6 Document manual verification notes
