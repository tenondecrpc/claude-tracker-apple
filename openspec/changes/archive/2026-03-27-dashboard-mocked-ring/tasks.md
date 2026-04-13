## 1. Data Models

- [x] 1.1 Create `Models.swift` in the `Shared/` folder with `SessionInfo` and `UsageState` structs. Ensure `Shared/` is correctly configured as a synchronized group in the Xcode project.
- [x] 1.2 Implement `SessionInfo` (formerly `SessionData`) with `Codable, Identifiable` conformance and all required fields.
- [x] 1.3 Implement `UsageState` with `Codable` conformance and `static var mock` computed property returning fresh dates on each access.

## 2. TokenStore

- [x] 2.1 Create `TokenStore.swift` as `@Observable @MainActor final class` with `sessions: [SessionInfo]`, `pendingCompletion: SessionInfo?`, and `usageState: UsageState` initialized to `.mock`.
- [x] 2.2 Verify no `@AppStorage` or `@Published` is used - persistence via `UserDefaults` + `JSONEncoder` is deferred to a later phase.

## 3. CompletionView

- [x] 3.1 Create `CompletionView.swift` showing `sessionInfo.inputTokens + outputTokens` total tokens and `sessionInfo.costUSD` formatted as currency.
- [x] 3.2 Add a tap gesture or button to dismiss (sets `store.pendingCompletion = nil` via the binding from `.sheet(item:)`).

## 4. Dashboard ContentView

- [x] 4.1 Replace the blank `ContentView.swift` body with a `ZStack`/`VStack` layout scaffold.
- [x] 4.2 Implement the primary usage ring using `Circle().trim(from: 0, to: store.usageState.utilization5h).stroke(style: StrokeStyle(lineWidth: 7, lineCap: .round))`.
- [x] 4.3 Add the secondary 7-day inner ring using a smaller `Circle().trim` with reduced `lineWidth`.
- [x] 4.4 Wrap the reset countdown text in a `TimelineView(.periodic(from: Date(), by: 60))` so it updates every minute.
- [x] 4.5 Implement `formatCountdown(to:)` helper that returns "Xhr Ymin left", "Ymin left", or "Resetting…" based on time remaining.
- [x] 4.6 Add the `⚠ mock` badge (small `.caption2` text) conditionally when `store.usageState.isMocked == true`.
- [x] 4.7 Wire `.sheet(item: $bindableStore.pendingCompletion)` to present `CompletionView` using `@Bindable` and explicit type annotations for compiler stability.

## 5. Wiring & Previews

- [x] 5.1 Instantiate `TokenStore` with `@State private var store = TokenStore()` in `ContentView` and use `@Bindable` for properties requiring bindings.
- [x] 5.2 Add `#Preview` for `ContentView` showing the mocked dashboard.
- [x] 5.3 Add `#Preview` for `CompletionView` with a sample `SessionInfo`.
- [x] 5.4 Build the Watch Extension target in Xcode and confirm no compiler errors.
