# CLAUDE.md

## Project

Apple Watch app that tracks Claude Code token/credit usage and delivers haptic alerts when a session ends.

**Pipeline**: macOS app (OAuth + poll) → iCloud JSON → iOS companion → WatchConnectivity (`transferUserInfo`) → watchOS haptic + UI

See `docs/FUTURE_PLAN.md` for the full roadmap.

## Build

Open `ClaudeTracker.xcodeproj` in Xcode. No CLI build system.

> **macOS target**: requiere "Outgoing Connections (Client)" activado en App Sandbox (Signing & Capabilities) para que las llamadas HTTP a `platform.claude.com` funcionen.

## Targets

| Folder | Target | Role |
|---|---|---|
| `ClaudeTracker macOS/` | macOS menu bar app | OAuth sign-in, usage polling, iCloud writer |
| `ClaudeTracker/` | iOS app | iCloud reader (`NSMetadataQuery`), WatchConnectivity sender |
| `ClaudeTracker Watch/` | watchOS app shell | Entry point only |
| `ClaudeTracker Watch Extension/` | watchOS extension | All watch UI and logic |

## Shared Logic

Code shared between targets lives in `Shared/`. The project uses `PBXFileSystemSynchronizedRootGroup` — files added to `Shared/` are automatically included in all linked targets, no manual Target Membership needed.

**Belongs in `Shared/`:** data models, pure business logic (no `UIKit`/`WatchKit`/`SwiftUI`), shared enums/constants.

**Does NOT belong in `Shared/`:** views, `WCSession` logic, iCloud/`NSMetadataQuery` code, haptic code.

## Technical Patterns

### SwiftUI @Observable & Bindings
- **Problem**: Compiler fails to infer types or provide bindings for `@Observable` properties in `@State`.
- **Solution**: Use `@Bindable` inside `body` with explicit type annotations in closures.
  ```swift
  var body: some View {
      @Bindable var bindableStore = store
      ...
      .sheet(item: $bindableStore.pendingCompletion) { (item: SessionInfo) in ... }
  }
  ```

## Workflow

- **Design**: use `/opsx:propose` to draft changes before implementing
- **SwiftUI**: invoke `/swiftui-expert-skill` when writing or reviewing any Swift/SwiftUI code
