# Bugfix Requirements Document

## Introduction

After the multi-account-support change landed in the Tempo for Claude macOS app, launching the app on a machine that has only Claude Code CLI credentials (and no Tempo OAuth accounts in `AccountRegistry`) leaves the app in an inconsistent half-signed-in state. `tryRestoreSession()` in `Tempo macOS/MacOSAPIClient.swift` flips `authState.isAuthenticated = true` and `authState.authSource = .cliSession` on the CLI fallback path without registering any account in `AccountRegistry`. The rest of the multi-account UI assumes `authState.isAuthenticated == true` implies the registry has at least one account, so the menu bar popover simultaneously renders "Not signed in" (because there is no active account label), the "Fetching usage..." spinner (driven by `isAuthenticated`), and a `Logout` row (also driven by `isAuthenticated`). In parallel, `AccountRegistryICloudMirror` writes `Tempo/accounts/index.json` with `count=0` on every launch, producing iCloud write thrash and a misleading empty index.

This bug was an oversight during tasks 2.x / 3.x of the multi-account-support change: the CLI fallback branch was not migrated alongside the rest of the auth flow. The fix must restore the invariant that `authState.isAuthenticated == true` implies `AccountRegistry.accounts` is non-empty, either by registering a synthetic CLI-backed account (tagged via `AccountIdentifier.cliFallbackAccountId(from:)`) or by treating CLI-only credentials as "not signed in" for the multi-account UI. The fix must not refresh or mutate Claude Code CLI credentials (per `docs/AUTH_FLOW.md`) and must not write `accounts/index.json` with `count=0` as a byproduct of a CLI-only restore.

The log line `writeIndex wrote file path=.../Tempo/accounts/index.json count=0` is a leading observable signal that the bug has regressed and should be treated as a canary in future verification.

## Bug Analysis

### Current Behavior (Defect)

What currently happens when the app launches on a machine with only Claude Code CLI credentials and no Tempo OAuth accounts in the registry.

1.1 WHEN the app launches on a machine with only Claude Code CLI credentials and no Tempo OAuth accounts in `AccountRegistry` THEN the system sets `authState.isAuthenticated = true` and `authState.authSource = .cliSession` in the `tryRestoreSession()` CLI fallback block without registering any account in `AccountRegistry`, leaving `AccountRegistry.accounts` empty while `authState.isAuthenticated` is true.

1.2 WHEN `authState.isAuthenticated == true` AND `AccountRegistry.accounts.isEmpty == true` after `tryRestoreSession()` returns THEN the menu bar popover renders the Account row label as "Not signed in" because there is no active account, while simultaneously rendering the usage fetching panel with "Fetching usage..." and including a `Logout` action row, producing a visibly inconsistent half-signed-in state.

1.3 WHEN the CLI-only restore path completes on launch THEN `AccountRegistryICloudMirror` writes `Tempo/accounts/index.json` with `count=0` as a byproduct of the restore flow, even though no registry mutation was intended.

1.4 WHEN the app is launched repeatedly in this CLI-only state THEN `Tempo/accounts/index.json` is re-written with `count=0` on every launch, producing iCloud write thrash and emitting the `writeIndex wrote file path=.../Tempo/accounts/index.json count=0` trace each time.

1.5 WHEN `AccountRegistry.accounts.isEmpty == true` AND `authState.isAuthenticated == true` THEN the popover exposes a `Logout` affordance whose target is a registry with zero accounts, giving the user a sign-out control over nothing.

1.6 WHEN the CLI fallback branch runs THEN it bypasses `AccountIdentifier` canonicalization (for example `cliFallbackAccountId(from:)` and `unassignedAccountId`) that the rest of the multi-account system relies on to identify the active account across the popover, registry, iCloud index, and widget snapshot.

### Expected Behavior (Correct)

What should happen instead when the app launches on a machine with only Claude Code CLI credentials.

2.1 WHEN the app launches on a machine with only Claude Code CLI credentials and no Tempo OAuth accounts in `AccountRegistry` THEN the system SHALL either (a) register a synthetic CLI-backed account in `AccountRegistry` tagged with `AccountIdentifier.cliFallbackAccountId(from:)` so that `authState.isAuthenticated`, the popover Account row, the registry, the iCloud index, and the widget snapshot all agree, OR (b) leave `authState.isAuthenticated == false` and present a coherent signed-out state that prompts the user to complete Tempo OAuth.

2.2 WHEN `tryRestoreSession()` returns THEN the system SHALL guarantee the invariant that `authState.isAuthenticated == true` implies `AccountRegistry.accounts.count >= 1`, so the half-signed-in state described in 1.2 is not reachable.

2.3 WHEN the CLI-only restore path runs THEN the system SHALL NOT write `Tempo/accounts/index.json` with `count=0` as a byproduct; `AccountRegistryICloudMirror` SHALL only write the index when it reflects a non-empty registry or an intentional user-initiated clear.

2.4 WHEN the app is launched repeatedly in the CLI-only state after the fix THEN the system SHALL NOT emit `writeIndex wrote file ... count=0` on every launch; that log line SHALL be treated as a leading observable signal for regression detection and SHALL only occur as a result of an intentional registry clear.

2.5 WHEN the CLI-only restore path results in a signed-in state (option 2.1.a) THEN the popover SHALL render a single coherent state: a named or placeholder CLI account in the Account row, a usage panel bound to that account, and a `Logout` row that targets the synthetic CLI account.

2.6 WHEN the CLI-only restore path results in a signed-out state (option 2.1.b) THEN the popover SHALL NOT show the `Fetching usage...` spinner and SHALL NOT show a `Logout` action row; it SHALL show a clear Tempo OAuth sign-in affordance.

2.7 WHEN the CLI fallback path runs THEN the system SHALL NOT refresh, mutate, or write back Claude Code CLI credentials; CLI credentials remain read-only per `docs/AUTH_FLOW.md`.

### Unchanged Behavior (Regression Prevention)

Existing behavior that must be preserved by the fix.

3.1 WHEN one or more Tempo OAuth accounts are already stored THEN the system SHALL CONTINUE TO restore each account via the per-account web OAuth restore path and populate `AccountRegistry` with those accounts on launch.

3.2 WHEN Claude Code CLI credentials exist in the system Keychain THEN the system SHALL CONTINUE TO read them via the Security framework (`ClaudeCodeKeychainReader`) without refreshing, rotating, or writing them.

3.3 WHEN computing account identifiers THEN the system SHALL CONTINUE TO use `AccountIdentifier` canonicalization, including `cliFallbackAccountId(from:)` and `unassignedAccountId`, so identifiers remain stable across the popover, registry, iCloud index, and widget snapshot.

3.4 WHEN polling usage THEN the system SHALL CONTINUE TO drive polling from `AccountRegistry` state (registry-based polling) rather than from `authState` alone.

3.5 WHEN storing OAuth credentials THEN the system SHALL CONTINUE TO keep them in the Keychain only and never in `UserDefaults`, widget storage, or iCloud.

3.6 WHEN `AccountRegistry` contains one or more accounts and its contents change THEN the system SHALL CONTINUE TO mirror the registry to iCloud at `Tempo/accounts/index.json` with the correct non-zero count via `AccountRegistryICloudMirror`.

3.7 WHEN the user completes Tempo OAuth sign-in after a CLI-only launch THEN the system SHALL CONTINUE TO transition into a fully signed-in multi-account state with a coherent popover, registry, iCloud index, and widget snapshot.

3.8 WHEN sharing code across targets THEN the fix SHALL CONTINUE TO respect the `Shared/` boundary: watch relay and haptic logic SHALL NOT be moved into `Shared/`, and OAuth credentials SHALL NOT leak into shared storage.
