## 1. TokenStore — apply method

- [x] 1.1 Add `func apply(_ state: UsageState)` to `TokenStore` that assigns `usageState = state`

## 2. WatchSessionReceiver — new file

- [x] 2.1 Create `ClaudeTracker Watch Extension/WatchSessionReceiver.swift` with `final class WatchSessionReceiver: NSObject, WCSessionDelegate`
- [x] 2.2 Implement `init(store: TokenStore)` — guard `WCSession.isSupported()`, set delegate, call `activate()`
- [x] 2.3 Implement `session(_:didReceiveUserInfo:)` — check `"type" == "UsageState"`, decode, dispatch `Task { @MainActor in store.apply(state) }`
- [x] 2.4 Add required stub methods for `WCSessionDelegate` (`sessionReachabilityDidChange`, `sessionDidBecomeInactive`, `sessionDidDeactivate` — no-ops)

## 3. Watch App — wiring

- [x] 3.1 Add `@State private var store = TokenStore()` to `Claude_Tracker_WatchApp`
- [x] 3.2 Add `@State private var receiver: WatchSessionReceiver?` and initialize it with the store in `.onAppear` (or as a stored property using a lazy init pattern)
- [x] 3.3 Inject `store` into `ContentView` via `.environment(store)` or direct parameter

## 4. Verification

- [ ] 4.1 Build Watch Extension target — confirm no compile errors
- [ ] 4.2 Run on simulator or device — confirm `WCSession.activate()` is called at launch (no crash)
- [ ] 4.3 Trigger a usage sync from iOS — confirm watch dashboard ring updates and mock badge disappears
