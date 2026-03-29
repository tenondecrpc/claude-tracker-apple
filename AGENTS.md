# AGENTS.md

This file provides guidelines for agentic coding agents operating in this repository.

## Project Overview

Apple Watch app that tracks Claude Code token/credit usage and delivers haptic alerts when a session ends.

**Pipeline**: macOS app (OAuth + poll) → iCloud JSON → iOS companion → WatchConnectivity (`transferUserInfo`) → watchOS haptic + UI

## Build & Development

### Opening the Project

```bash
open ClaudeTracker.xcodeproj
```

### Running the App

- Select target in Xcode scheme selector (top-left)
- Press `Cmd+R` to build and run
- Requires Xcode 15+ for SwiftUI development

### Targets

| Folder | Target | Role |
|---|---|---|
| `ClaudeTracker macOS/` | macOS menu bar app | OAuth sign-in, usage polling, iCloud writer |
| `ClaudeTracker/` | iOS app | iCloud reader (`NSMetadataQuery`), WatchConnectivity sender |
| `ClaudeTracker Watch/` | watchOS app shell | Entry point only |
| `ClaudeTracker Watch Extension/` | watchOS extension | All watch UI and logic |

### Testing

- No formal test suite exists yet
- For watchOS haptic testing, run on physical device or Apple Watch simulator

## Code Style Guidelines

### General Principles

- Prefer SwiftUI over UIKit/WatchKit for all views
- Use `@Observable` for state management (macOS 14+, iOS 17+, watchOS 10+)
- Keep views simple; push logic into dedicated coordinator/service classes

### Imports

```swift
import SwiftUI        // Required for all views
import Foundation     // Required for data types, networking
import WatchConnectivity  // Required for Watch relay
```

Group imports by framework, sorted alphabetically within groups.

### File Organization

1. Imports at top
2. MARK comments for logical sections (`// MARK: - SectionName`)
3. Type definitions (structs, classes, enums)
4. Extensions for protocol conformances
5. Private helpers at end of file

### Naming Conventions

- **Types** (structs, classes, enums): `PascalCase` (e.g., `SessionInfo`, `AuthError`)
- **Properties/variables**: `camelCase` (e.g., `isAuthenticated`, `utilization5h`)
- **Constants**: `camelCase` for static properties, `PascalCase` for enum cases
- **Files**: Match type name (e.g., `AuthState.swift` contains `AuthState`)

### SwiftUI Patterns

**@Observable with Bindings**:
```swift
var body: some View {
    @Bindable var bindableStore = store
    ...
    .sheet(item: $bindableStore.pendingCompletion) { (item: SessionInfo) in ... }
}
```

**View Organization**:
- Use computed properties for view variants (`private var waitingView: some View`)
- Use `some View` return types
- Prefer `.foregroundStyle()` over `.foregroundColor()`

### Type Annotations

- Prefer explicit types in closures for compiler stability:
  ```swift
  .sheet(item: $bindableStore.pendingCompletion) { (item: SessionInfo) in ... }
  ```
- Use property wrappers (`@State`, `@Bindable`, `@Published`) consistently

### Error Handling

- Define custom errors as `enum SomeError: LocalizedError`
- Implement `var errorDescription: String?` with `switch` for each case
- Use `async/await` with `try` for async operations
- Never swallow errors silently; log or propagate

Example from codebase:
```swift
enum AuthError: LocalizedError {
    case noToken
    case invalidCallback
    case tokenExchangeFailed

    var errorDescription: String? {
        switch self {
        case .noToken: return "No authentication token. Please sign in."
        case .invalidCallback: return "Invalid authorization callback."
        case .tokenExchangeFailed: return "Failed to exchange authorization code."
        }
    }
}
```

### Shared Code

Code shared between targets lives in `Shared/`. The project uses `PBXFileSystemSynchronizedRootGroup`.

**Belongs in `Shared/`:**
- Data models (`Codable`, `Identifiable`)
- Pure business logic (no `UIKit`/`WatchKit`/`SwiftUI`)
- Shared enums/constants

**Does NOT belong in `Shared/`:**
- Views
- `WCSession` logic
- iCloud/`NSMetadataQuery` code
- Haptic code

### Architecture

- **App entry**: `@main` struct with `App` protocol
- **Coordinators**: `@MainActor` classes that wire components together
- **State**: `@Observable` classes for view state, `@Published` for Combine interop
- **Services**: Protocol-based for testability (e.g., `iCloudUsageReader`)

### Workflow

- **Design**: Use `/opsx:propose` to draft changes before implementing
- **SwiftUI**: Invoke `/swiftui-expert-skill` when writing or reviewing any Swift/SwiftUI code
- **Changes**: Use `/opsx:apply` to implement tasks from OpenSpec change documents
