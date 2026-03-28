## ADDED Requirements

### Requirement: WatchSessionReceiver activates WCSession on watchOS
`WatchSessionReceiver` SHALL be a `final class` conforming to `WCSessionDelegate`. Its initializer SHALL call `WCSession.default.activate()` (guarded by `WCSession.isSupported()`). It SHALL store the delegate reference on `WCSession.default.delegate` before activating.

#### Scenario: Session activation at init
- **WHEN** `WatchSessionReceiver(store:)` is called
- **THEN** `WCSession.default.activate()` is called and the receiver is set as delegate

#### Scenario: Unsupported device guard
- **WHEN** `WCSession.isSupported()` returns false
- **THEN** `WatchSessionReceiver.init` returns without calling activate (no crash)

### Requirement: Receiver routes UsageState payloads to TokenStore
`WatchSessionReceiver` SHALL implement `session(_:didReceiveUserInfo:)`. When the payload contains `"type": "UsageState"`, it SHALL decode a `UsageState` from the dictionary and call `store.apply(_:)` on the `@MainActor`.

#### Scenario: Valid UsageState payload received
- **WHEN** `didReceiveUserInfo` fires with `["type": "UsageState", ...]`
- **THEN** `TokenStore.apply(_:)` is called with the decoded `UsageState`

#### Scenario: Unknown type payload ignored
- **WHEN** `didReceiveUserInfo` fires with `["type": "SomeFutureType", ...]`
- **THEN** the payload is silently ignored and `TokenStore` is not modified

#### Scenario: Missing type key ignored
- **WHEN** `didReceiveUserInfo` fires with a payload that has no `"type"` key
- **THEN** the payload is silently ignored and `TokenStore` is not modified

### Requirement: Main actor dispatch for store mutation
`WatchSessionReceiver` SHALL dispatch the `store.apply(_:)` call to `@MainActor` using `Task { @MainActor in ... }` since `WCSessionDelegate` methods are called on a background thread.

#### Scenario: Background thread delivery
- **WHEN** `didReceiveUserInfo` is invoked on a background thread
- **THEN** `TokenStore.apply(_:)` executes on the main actor without data races

### Requirement: WatchSessionReceiver is instantiated at app launch
`Claude_Tracker_WatchApp` SHALL hold a `WatchSessionReceiver` as a stored property (not a local) so it lives for the lifetime of the app. The receiver SHALL be injected with the shared `TokenStore`.

#### Scenario: Receiver lifetime
- **WHEN** the watch app launches
- **THEN** `WatchSessionReceiver` is initialized once and retained for the app's lifetime

### Requirement: TokenStore is injected into the view hierarchy
`Claude_Tracker_WatchApp` SHALL hold a `TokenStore` and pass it into the `ContentView` via `.environment(_:)` or direct initializer injection so all views share a single store instance.

#### Scenario: Single store instance
- **WHEN** the watch app launches
- **THEN** all views read from the same `TokenStore` instance that the receiver writes to
