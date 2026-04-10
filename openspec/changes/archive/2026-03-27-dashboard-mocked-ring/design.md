## Context

The watchOS target currently contains a blank SwiftUI template. Phase 3 of the roadmap calls for the main dashboard: a usage ring, reset countdown, and session completion sheet. Real data (OAuth API, WatchConnectivity) comes in later phases; this change delivers the full UI against a mock `UsageState` so the watch face is immediately functional and all downstream UI work can build on it.

The project uses the modern `@Observable` macro (not `ObservableObject`), targets watchOS via the Watch Extension target, and follows the SwiftUI patterns documented in `.agents/skills/swiftui-expert-skill/references/`.

## Goals / Non-Goals

**Goals:**
- Implement `TokenStore` as an `@Observable @MainActor` class with a static mock `UsageState`
- Implement `ContentView` as a dashboard with a circular progress ring, `⚠ mock` badge, and reset countdown
- Implement `CompletionView` as a full-screen sheet stub (shown when `pendingCompletion != nil`)
- Keep all new code watchOS-only (Watch Extension target)

**Non-Goals:**
- WatchConnectivity integration (Phase 3 real data)
- OAuth polling or real `UsageState` (Phase 7)
- Haptic triggers (Phase 3 — separate from the UI)
- Complications (Phase 5)
- Persistence to `UserDefaults` (can be added in Phase 3 without UI changes)

## Decisions

### `@Observable` over `ObservableObject`
Using the `@Observable` macro (`import Observation`) instead of `ObservableObject` + `@Published`. Rationale: the roadmap explicitly requires `@Observable @MainActor`, and the macro enables fine-grained dependency tracking. Consequence: `@AppStorage` cannot be used inside the class — `UserDefaults` + `JSONEncoder` must be used directly for persistence later.

### Static mock via computed `var` not `let`
`UsageState.mock` is a `static var` (not `let`) so `Date()` is evaluated fresh on each access. A `let` would freeze the mock countdown at first use, making the timer appear incorrect in Previews and during development. The roadmap explicitly calls this out.

### Ring drawn with `Circle` + `.trim` + `Canvas` overlay
A `Circle().trim(from:to:).stroke(style: StrokeStyle(lineWidth:, lineCap:))` is the idiomatic SwiftUI approach for a progress ring on watchOS. No third-party dependency needed. Primary ring = `utilization5h`; secondary indicator = `utilization7d` as a thinner inner ring.

### `⚠ mock` badge always visible when `isMocked == true`
The badge is an explicit contract: the watch face must never look "real" while showing mocked data. It should be visible at all times (not hidden behind interaction), shown as a small text overlay inside the ring or below the countdown.

### `CompletionView` as `.sheet(item:)`
`pendingCompletion` is `var SessionInfo?` on `TokenStore`. `ContentView` provides a binding via a local `@Bindable var bindableStore = store` within the `body` to avoid shadowing and help type inference. Explicit type annotation `(item: SessionInfo) in` is used in the closure to ensure compiler stability. Dismissal sets `pendingCompletion = nil`, which matches the roadmap pattern.

### Project Structure & Naming
- **Naming**: `SessionData` was renamed to `SessionInfo` to ensure clear distinction and avoid scoping issues during target consolidation.
- **Shared Folder**: Logic shared between targets lives in `Shared/Models.swift`. The `Shared` folder is explicitly configured as a `PBXFileSystemSynchronizedRootGroup` in the Xcode project and linked to all targets to ensure visibility without manual file membership management.

## Risks / Trade-offs

- **Ring appearance on small watch faces** → Use compact `lineWidth` (6–8pt) and verify in 41mm and 45mm previews. Mitigation: add `#Preview` with explicit `previewDevice`.
- **`@Observable` and `@State` interaction** → `TokenStore` should be instantiated with `@State private var store = TokenStore()` in the root view (not `@StateObject`). Mitigation: follow the `@Observable` state management reference.
- **Countdown display drift** — `TimelineView` or a `Timer`-based approach needed to keep countdown live. Using `TimelineView(.periodic(from:by:))` is the watchOS-idiomatic choice. Mitigation: wrap countdown text in a `TimelineView` with 60-second cadence.

## Open Questions

- Which watch target is the "real" one? There appear to be two: `Tempo Watch/` and `Tempo Watch Extension/`. The roadmap references `tempo-for-claude-applewatch Watch App/` — needs confirmation at implementation time. Both currently contain identical blank templates; implement in the one that builds successfully.
