# Code Conventions & Technical Patterns

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

## Code Style

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

Example:
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

## Architecture

- **App entry**: `@main` struct with `App` protocol
- **Coordinators**: `@MainActor` classes that wire components together
- **State**: `@Observable` classes for view state, `@Published` for Combine interop
- **Services**: Protocol-based for testability (e.g., `iCloudUsageReader`)
