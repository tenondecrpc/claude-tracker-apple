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

## Multi-Account

Tempo treats multi-account as the only supported shape. There is no legacy single-account fallback. See `openspec/changes/multi-account-support/` for the full design.

### Account Identifiers

Canonical `accountId` is produced by `Shared/AccountIdentifier.swift` and is the single key used by Keychain slots, iCloud paths, widget snapshots, and WatchConnectivity payloads.

- `AccountIdentifier.canonicalize(email:)`: NFC normalize, trim, lowercase. Throws `AccountIdentifierError.emptyEmail` when the result is empty.
- `AccountIdentifier.cliFallbackAccountId(from:)`: deterministic `cli-local-<8 hex>` used only when the OAuth profile has no email.
- `AccountIdentifier.unassignedAccountId = "unassigned"`: sentinel for session-scoped payloads (`SessionInfo`, `LocalProjectStat`) that cannot be matched to a registered account. Never applied to `UsageState`.
- `AccountIdentifier.percentEncodedDirectoryName(for:)`: filesystem-safe form used only when building directory names. The in-memory `accountId` stays canonical.

### iCloud Layout

Per-account tree under the `iCloud.com.tenondev.tempo.claude` container, rooted at `Documents/Tempo/`. All per-account URLs are built by helpers on `Shared/TempoICloud.swift`. The flat legacy paths (`Tempo/usage.json`, `Tempo/usage-history.json`, `Tempo/latest.json`) are never read or written.

```
Tempo/
  accounts/
    index.json                       <- AccountsIndexFile, ordered accountIds
    <percentEncodedAccountId>/
      account.json                   <- non-secret metadata {accountId, email, displayName, createdAt}
      usage.json                     <- current UsageState
      usage-history.json             <- per-account history
      latest.json                    <- latest relayed Claude Code session
  alert-preferences.json             <- global, not per-account
  appearance-mode.json               <- global, not per-account
```

`alert-preferences.json` and `appearance-mode.json` are intentionally global. Any files directly under `Tempo/` that are not one of those two are stale.

### Keychain (macOS)

All OAuth slots live under service `com.tenondev.tempo.claude.oauth`.

| `kSecAttrAccount` | Owner | Contents |
|---|---|---|
| canonical `accountId` | `CredentialStore` | JSON-encoded `StoredCredentials` for that account |
| `__registry__` | `AccountRegistry` | JSON-encoded `[Account]` (non-secret) |

The `__registry__` slot is reserved. It is the only non-credential slot under this service and is never treated as an account. Credentials never leave macOS (no iCloud, no widget storage, no `UserDefaults`).

### Registry Ownership

- `Tempo macOS/AccountRegistry.swift` owns the account list on macOS. It is the single source of truth for add, remove, rename, and `activeAccountId`. Persisted to the Keychain `__registry__` slot.
- `Tempo macOS/AccountRegistryICloudMirror.swift` mirrors non-secret metadata to iCloud: it writes `accounts/<id>/account.json` and rebuilds `accounts/index.json` on every registry change.
- `Tempo macOS/AccountRemovalService.swift` is the single entry point for sign-out. It deletes the per-account Keychain slot via `CredentialStore`, the per-account iCloud directory, and the account from the registry. `MacOSAPIClient.signOut(for:)` goes through this service.
- iOS does not hold tokens and does not mutate the registry. It discovers accounts by reading `accounts/index.json` and the per-account files.

### Identity Convergence Across CLI and OAuth

A user who signs into Claude Code CLI today and completes Tempo OAuth tomorrow under the same Anthropic email MUST produce a single `AccountRegistry` row, a single per-account iCloud directory, and a single Keychain credential slot. Both paths build the `accountId` by canonicalizing `~/.claude.json` `oauthAccount.emailAddress` through `AccountIdentifier.canonicalize(email:)`, so the derived ids match byte for byte and `AccountRegistry.add` updates in place instead of creating a duplicate.

Reading `~/.claude.json` from the sandbox requires the `com.apple.security.temporary-exception.files.home-relative-path.read-only` entitlement scoped to `/.claude.json` in `Tempo macOS/Tempo macOS.entitlements`. If that entitlement is missing, the explicit CLI sign-in path falls back to a synthetic `cli-local-<hash>` id; once the canonical email becomes readable (entitlement restored or OAuth completed), the code in `MacOSAPIClient.tryRestoreSession(includeCLIFallback: true)` and `MacOSAPIClient.submitOAuthCode(_:)` migrates the synthetic row out via `AccountRemovalService` and replaces it with the canonical id.

See `docs/AUTH_FLOW.md` "Identity Convergence Across CLI and OAuth" for the full contract, migration semantics, and DevLog trace strings.

### iOS Active Account

`Tempo/IOSAppStore.swift` persists the selected account in `UserDefaults` under key `ios.activeAccountId`. The `resolvedAccountId` computed property returns the stored id when still present in `iCloudReader.knownAccountIds`, otherwise falls back to `knownAccountIds.first`. iCloud is read-only on iOS; account creation is macOS-only.

### Watch Active Account

The iPhone is the sole source of truth for the watch's active account. `Tempo/WatchRelayManager.swift` sends the current `UsageState` with `accountId` and `accountLabel` via `updateApplicationContext`. When the iPhone has no active account, it sends a `{"type": "NoActiveAccount"}` context; `Tempo Watch/WatchSessionReceiver.swift` routes that through `TokenStore.applyNoActiveAccount()` to clear watch-side state.

Completion alerts on the watch are gated on an active-account match. Sessions tagged with `AccountIdentifier.unassignedAccountId` (CLI-only) are exempted from the gate because they have no owning account.

### Widget Snapshots

Widget snapshot storage lives in `Shared/WidgetUsageSnapshot.swift`. Snapshots are per-account, keyed by canonical `accountId`, and a separate pointer file names the active account.

Layout inside the platform App Group container (`group.com.tenondev.tempo.claude.ioswidget` or `group.com.tenondev.tempo.claude.macwidget`):

```
Library/Application Support/Tempo/
  accounts/
    <percentEncodedAccountId>/
      tempo.widget.snapshot.json     <- WidgetUsageSnapshot (schemaVersion 3)
  active-account.json                <- pointer {activeAccountId}
```

- `TempoWidgetSnapshotStore.write(_:platform:)` writes a per-account snapshot. It does not flip the pointer.
- `TempoWidgetSnapshotStore.write(activeAccountId:platform:)` updates the pointer. Passing `nil` removes it.
- `TempoWidgetSnapshotStore.read(platform:)` reads the pointer, then the matching snapshot. `read(accountId:platform:)` reads a specific account.
- `WidgetUsageSnapshot` requires both `accountId` and `accountLabel`. A decode without these fields fails by design.

Widget pinning uses `Shared/SelectAccountIntent.swift` with `AppIntentConfiguration` on iOS and macOS. The watch widget uses `StaticConfiguration` and follows the iPhone-relayed account only. Do not convert the watch widget to `AppIntentConfiguration`.

### Widget Routes

Widget taps open deep links via `Shared/TempoWidgetRoute.swift`. The route carries the snapshot's `accountId` so the host app lands on the same account the widget was displaying.

- URL shape: `tempoforclaude://<kind>?accountId=<percentEncodedAccountId>`
- `kind` is `dashboard` (iOS) or `stats` (macOS). Encoded as the URL host so `handlesExternalEvents(matching:)` can match on the host string.
- Omitted or empty `accountId` means "follow the current active account".
- Host apps consume routes through `onOpenURL` on the relevant scene.
