# cli-session-registry-consistency-fix Bugfix Design

## Revision: Strategy shift from (b) to (a') with identity convergence

The initial design below adopted strategy (b) (treat CLI-only credentials as "not signed in"). Real-world testing surfaced two problems with (b):

1. Users with valid Claude Code CLI sessions were forced through Tempo OAuth even though they had working credentials, which is hostile UX and contradicts the `docs/AUTH_FLOW.md` contract that allows CLI as a read-only credential fallback.
2. The `isFirstLaunch` branch in `TempoMacApp.onLaunch()` skipped `tryRestoreSession()` entirely, so the CLI auto-add never ran on a fresh machine.

The shipped fix uses **strategy (a'): auto-register a CLI-backed account in the registry, using the canonical email from `~/.claude.json` as the `accountId`, with a deterministic `cli-local-<hash>` fallback when the email is unreadable and automatic migration to the canonical id when it becomes readable**. This preserves the invariant `isAuthenticated implies accounts.count >= 1` without forcing OAuth. Strategy (a) was rejected in the initial draft because it risked leaking a synthetic id into iCloud and widget snapshots; strategy (a') addresses that concern by migrating the synthetic id to the canonical email-backed id as soon as `~/.claude.json` becomes readable.

The four scoped code changes landed as described. Additional changes relative to the original design:

- `Tempo macOS/Tempo macOS.entitlements`: added `com.apple.security.temporary-exception.files.home-relative-path.read-only` for `/.claude.json` so the sandbox can read the canonical email. This is a high-risk entitlement change per AGENTS.md; it is narrow (one file, read-only) and is the minimum required to make identity convergence work under App Sandbox.
- `Tempo macOS/MacOSAPIClient.swift` `tryRestoreSession()` CLI branch: always auto-registers the account. Prefers the canonical email-backed id. Falls back to `cli-local-<hash>` only when the email is unreadable. Migrates any outstanding `cli-local-<hash>` registry row to the canonical id on every successful resolution.
- `Tempo macOS/MacOSAPIClient.swift` `submitOAuthCode(_:)`: runs the same `cli-local-<hash>` migration on successful OAuth so CLI-first / OAuth-later flows converge on a single registry row.
- `Tempo macOS/TempoMacApp.swift` `onLaunch()`: now always calls `tryRestoreSession()` (removed the `isFirstLaunch` short-circuit). When `restored == true`, sets `hasCompletedFirstLaunch` so future launches behave identically.

See `docs/AUTH_FLOW.md` "Identity Convergence Across CLI and OAuth" for the full contract and DevLog trace strings.

The rest of this document documents the original (b) strategy design for historical context. Where it conflicts with the revision above, the revision wins.

---

## Overview

After the multi-account-support change landed on macOS, `MacOSAPIClient.tryRestoreSession()` still contains a legacy CLI-session fallback block that flips `authState.isAuthenticated = true` and `authState.authSource = .cliSession` without registering any `Account` in `AccountRegistry`. On a machine that has only Claude Code CLI credentials in the system Keychain (no Tempo OAuth accounts), this breaks the implicit invariant that the rest of the multi-account UI relies on:

    authState.isAuthenticated == true implies AccountRegistry.accounts.count >= 1

Three observable symptoms follow from that broken invariant on every launch:

1. The menu bar popover simultaneously renders "Not signed in" in the Account row (because `registry.accounts` is empty), "Fetching usage..." in the body (because `authState.isAuthenticated` is true), and a `Logout` action row (also gated on `isAuthenticated`).
2. `AccountRegistryICloudMirror.writeMirror(for:)` is invoked unconditionally in `TempoMacApp.init` and again in `onLaunch()` after `tryRestoreSession` returns true. Both calls fan out to `writeIndex` with an empty registry, overwriting `Tempo/accounts/index.json` with `count=0` and emitting `writeIndex wrote file path=.../Tempo/accounts/index.json count=0` on every launch.
3. Users who previously relied on CLI-only tokens see an incoherent half-signed-in state and cannot actually sign out of anything meaningful, because `Logout` targets `registry.activeAccountId` which is `nil`.

This fix adopts strategy (b) from the bugfix requirements: treat CLI-only credentials as "not signed in" for the multi-account contract. The multi-account-support change already made multi-account the only supported shape and removed the single-account fallback as the sanctioned entry point. This bug is an incidental leftover of that migration, not a deliberate feature. Option (a), synthesizing a CLI-backed registry account, was rejected to keep the registry a faithful mirror of user-initiated Tempo OAuth sign-ins and to avoid leaking a synthetic `cli-local-<hash>` row into the iCloud `accounts/index.json`, widget snapshots, and iOS discovery where it would surface as a real account.

The fix has three independent code changes plus one defense-in-depth UI change:

1. Gate the CLI fallback branch in `tryRestoreSession()` on registry membership: the branch may set `isAuthenticated = true` only when the CLI profile's email resolves to an accountId already present in `AccountRegistry` (web OAuth already sanctioned this account; CLI is just a read-only token source for it). Otherwise the branch leaves `isAuthenticated = false`.
2. Gate `AccountRegistryICloudMirror.writeIndex` against empty-write thrash: when the in-memory registry is empty AND the current remote `index.json` is absent or already `count=0`, `writeIndex` becomes a no-op. Intentional user-initiated clears (the last account is removed via `AccountRemovalService`) still write through because in that case the remote index has `count >= 1` before the write.
3. Gate the coordinator-level mirror writes: the init-time seed in `TempoMacApp.init` runs only when `registry.accounts` is non-empty, and the post-restore write in `onLaunch()` runs only when `tryRestoreSession` actually promoted a registry account to active.
4. Defense in depth in the popover: gate the usage panel and `Logout` row on `!registry.accounts.isEmpty` rather than on `authState.isAuthenticated` alone, so a future regression of the invariant still renders a coherent UI.

Side effect acknowledged: any user who previously relied solely on CLI tokens (no Tempo OAuth sign-in) will be forced through Tempo OAuth on first launch after this fix lands. This is acceptable because the multi-account-support change already removed the single-account CLI-only contract; no migration path is provided.

## Glossary

- **Bug_Condition (C)**: After `tryRestoreSession()` returns, `authState.isAuthenticated == true AND AccountRegistry.accounts.isEmpty == true`.
- **Property (P)**: After `tryRestoreSession()` returns, `authState.isAuthenticated == true` implies `AccountRegistry.accounts.count >= 1`. `AccountRegistryICloudMirror.writeIndex` does not overwrite an already-empty remote index with another `count=0` payload. The popover body and `Logout` row never render when `registry.accounts.isEmpty`.
- **Preservation**: Per-account web OAuth restore, `ClaudeCodeKeychainReader` read-only semantics, `AccountIdentifier` canonicalization, registry-driven polling, iCloud mirror writes with correct non-zero counts, and Tempo-OAuth-to-signed-in transitions all remain unchanged for non-buggy inputs.
- **tryRestoreSession**: Function in `Tempo macOS/MacOSAPIClient.swift` that restores an authenticated session on launch. It first tries per-account web OAuth candidates from `registry` + `CredentialStore.knownAccountIds()`, then falls back to the legacy Claude Code CLI session path (the bug site).
- **AccountRegistry**: Observable in-memory list of Tempo accounts with an `activeAccountId`. Persisted via the `__registry__` Keychain slot. The single source of truth for known accounts on macOS.
- **AccountRegistryICloudMirror**: Best-effort writer that projects `AccountRegistry` to iCloud at `Tempo/accounts/<id>/account.json` and `Tempo/accounts/index.json`. `writeMirror(for:)` is the only public write entry point and always calls `writeIndex` internally.
- **writeIndex (private)**: Writes `Tempo/accounts/index.json` containing the ordered list of accountIds and a timestamp. Emits `writeIndex wrote file path=... count=N` via `DevLog.trace`. The `count=0` variant is the canary log line for this bug.
- **ClaudeCodeKeychainReader**: Read-only reader for Claude Code CLI credentials via the Security framework. Never writes, refreshes, or deletes Keychain entries. Must stay read-only per `docs/AUTH_FLOW.md`.
- **AccountIdentifier.cliFallbackAccountId(from:)**: Deterministic synthetic accountId of the form `cli-local-<shortHash>` derived from SHA256 of a seed (typically the CLI refresh token). Used elsewhere for canonicalization; explicitly NOT used by this fix to populate the registry.
- **authState.authSource**: Enum with cases `.none`, `.cliSession`, `.webOAuth`. After this fix, `.cliSession` is only reachable when the CLI email resolves to a registered accountId.

## Bug Details

### Bug Condition

The bug manifests when the app launches on a machine that has valid, unexpired Claude Code CLI credentials in the system Keychain but zero Tempo OAuth accounts in `AccountRegistry`. The CLI fallback block in `tryRestoreSession()` promotes the app to "authenticated" state without registering any account, leaving downstream UI, iCloud mirror writes, and logout wiring pointed at an empty registry.

**Formal Specification:**
```
FUNCTION isBugCondition(input)
  INPUT: input is a launch scenario consisting of:
    - cliTokens: optional ClaudeCodeKeychainReader.Tokens (may be absent or present+fresh+expired)
    - webCredentials: map of accountId -> StoredCredentials (may be empty)
    - registryAccounts: list of Account (the persisted __registry__ Keychain slot, may be empty)
  OUTPUT: boolean

  // Reproduce the full restore pipeline on "input":
  state := runTryRestoreSession(input)

  RETURN state.authState.isAuthenticated == true
         AND state.registry.accounts.isEmpty == true
END FUNCTION
```

The bug condition is satisfied, concretely, when:

- `registryAccounts` is empty AND `webCredentials` is empty (no per-account web slot is usable), AND
- `cliTokens` is present AND `ClaudeCodeKeychainReader.isAccessTokenFresh(cliTokens) == true`.

In that case the CLI fallback block at `Tempo macOS/MacOSAPIClient.swift` lines ~364-378 sets `authState.isAuthenticated = true` and returns `true` without touching `registry`.

### Examples

- CLI-only dev machine, cold launch: `ClaudeCodeKeychainReader.loadTokens()` returns fresh tokens, `CredentialStore.knownAccountIds()` returns `[]`, `registry.accounts` is empty. Expected: popover shows "Not Signed In" with Sign In button, no `count=0` write. Actual: popover shows "Not signed in" in the Account row AND "Fetching usage..." in the body AND a `Logout` row, and `index.json` is written with `count=0`.
- Same machine, second launch: same as above, plus a second `writeIndex wrote file ... count=0` log line.
- Machine that had Tempo OAuth then the user manually removed the account but CLI tokens remained: same half-signed-in state on next launch.
- Edge case, CLI tokens expired: `isAccessTokenFresh` returns `false`, fallback block already returns `false` correctly. Not part of the bug condition; this path is preserved by the fix.

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**

- Per-account web OAuth restore (`restoreAccount(accountId:allowRefresh:)`) continues to work for any registered account with valid or refreshable credentials.
- `ClaudeCodeKeychainReader` remains read-only: no write, rotate, or delete from any code path reachable from `tryRestoreSession()`.
- `AccountIdentifier.canonicalize(email:)`, `cliFallbackAccountId(from:)`, and `unassignedAccountId` remain the only account-id constructors used across popover, registry, iCloud index, and widget snapshots.
- `UsagePoller` continues to be driven by `AccountRegistry` state, not by `authState.isAuthenticated` alone.
- OAuth credentials continue to live only in the per-account Keychain slot; never in `UserDefaults`, widget storage, or iCloud.
- `AccountRegistryICloudMirror` continues to write a correct non-zero `index.json` whenever the registry actually has one or more accounts, and continues to emit `writeIndex wrote file path=... count=N` with `N >= 1` for those writes.
- After the user completes Tempo OAuth following a CLI-only launch, the app transitions into a fully signed-in multi-account state with a coherent popover, registry, iCloud index, and widget snapshot.
- Intentional user-initiated registry clears (removing the last account via `AccountRemovalService`) continue to flush `index.json` to `count=0` exactly once.

**Scope:**

All inputs that do NOT satisfy the bug condition must be completely unaffected by this fix. This includes:

- Launches with one or more Tempo OAuth accounts in the registry (regardless of whether CLI tokens also exist).
- Launches with no CLI tokens at all.
- Launches where CLI tokens are present but expired.
- Launches where the user has never signed in (fresh install).
- Any non-launch flow: OAuth code exchange, per-account sign-out, add-account, demo mode, preferences, widgets, polling, iCloud writers other than `index.json`.
- Any iOS, watchOS, iOS widget, or macOS widget code path.
- `AccountRegistryICloudMirror.writeAccountMetadata` (per-account `account.json`) is outside this fix; only `writeIndex` gains an empty-write guard.

## Hypothesized Root Cause

Based on the bug description and the code inspection summarized above, the most likely issues are, in order of confidence:

1. **Legacy CLI fallback branch not migrated**: The block at `Tempo macOS/MacOSAPIClient.swift` lines ~364-378 was preserved verbatim from the single-account world during the multi-account-support change. In the single-account world there was no registry, so "authenticated via CLI" was a complete state. In the multi-account world, `AccountRegistry` is the canonical source of truth and this block now produces a broken invariant whenever it is reached.
2. **Unconditional init-time mirror seed**: `TempoMacApp.init` ends with `accountMirror.writeMirror(for: registry)` to "seed the iCloud mirror once at startup so iOS discovery is correct even if the user never mutates the registry in this session." At init, `registry` has just been constructed and is empty in any launch where web OAuth restore has not yet populated it. `writeMirror(for:)` delegates to `writeIndex` unconditionally, producing `count=0` on every launch where no account is seeded synchronously. This is the primary producer of the `count=0` canary log line and is independent of the CLI fallback.
3. **Post-restore mirror write assumes `restored == true` implies non-empty registry**: `onLaunch()` calls `accountMirror.writeMirror(for: registry)` immediately after `tryRestoreSession()` returns `true`. When the CLI fallback path is what caused `true`, the registry is still empty, producing a second `count=0` write.
4. **UI gating uses `isAuthenticated` alone**: `SignInView` shows the dashboard when `authState.isAuthenticated`, and inside the dashboard the `Logout` row and the usage panel are gated on `latestUsage`/`lastPollError` without reference to `registry.accounts.isEmpty`. When the invariant breaks, the UI has no fallback.

## Correctness Properties

Property 1: Bug Condition - Registry Consistency After Restore

_For any_ launch scenario where the registry starts empty, no usable per-account web credentials exist, and CLI tokens exist in any state (absent, fresh, expired), after `tryRestoreSession()` returns the fixed `MacOSAPIClient` SHALL satisfy: `authState.isAuthenticated == true` implies `registry.accounts.count >= 1`. Equivalently, the CLI fallback branch SHALL NOT set `isAuthenticated = true` unless the CLI profile's email resolves to an accountId that is already in `registry`.

**Validates: Requirements 2.1, 2.2, 2.5, 2.6**

Property 2: Preservation - Non-Thrashing Empty Index Writes

_For any_ invocation of `AccountRegistryICloudMirror.writeMirror(for:)` where `registry.accounts.isEmpty == true`, the fixed mirror SHALL call `writeIndex` AT MOST ONCE across the lifetime of a remote index state that is already `count == 0` (or absent). Specifically, if the current remote `index.json` is absent or has `count == 0`, the fixed `writeIndex` SHALL be a no-op and SHALL NOT emit `writeIndex wrote file path=... count=0`. If the current remote index has `count >= 1` (intentional clear), the write SHALL proceed exactly once to flush `count=0`.

**Validates: Requirements 2.3, 2.4, 3.6**

Property 3: Preservation - CLI Keychain Read-Only

_For any_ launch scenario, no code path reachable from `tryRestoreSession()` SHALL write, refresh, rotate, or delete Claude Code CLI Keychain entries. The only CLI Keychain access SHALL be through `ClaudeCodeKeychainReader.loadTokens()` and `ClaudeCodeKeychainReader.isAccessTokenFresh(_:)`, both of which are read-only.

**Validates: Requirements 2.7, 3.2**

Property 4: Preservation - Popover Coherence Invariant

_For any_ UI render where `registry.accounts.isEmpty == true`, the dashboard popover SHALL NOT render the `Fetching usage...` spinner, SHALL NOT render the usage ring or burn-rate cards, and SHALL NOT render the `Logout` action row. This holds even if a future regression re-introduces `authState.isAuthenticated == true AND registry.accounts.isEmpty == true`.

**Validates: Requirements 2.5, 2.6, 1.2, 1.5**

## Fix Implementation

### Changes Required

Assuming the root cause analysis above is correct, the fix spans four files. Scope estimates are lines-of-change, not total lines.

**File**: `Tempo macOS/MacOSAPIClient.swift`

**Function**: `tryRestoreSession()`

**Specific Changes** (approx. 15-25 LOC):

1. **Gate the CLI fallback branch on registry membership**: Before setting `authState.isAuthenticated = true` with `.cliSession`, resolve the CLI profile's email via `DetectedClaudeAccount.load()` and canonicalize through `AccountIdentifier.canonicalize(email:)`. If the canonical id is present in `registry.accounts`, promote that accountId to active (if not already), set `authState.isAuthenticated = true`, `authState.authSource = .cliSession`, and return `true`. Otherwise, leave `authState.isAuthenticated = false`, `authState.authSource = .none`, trace `"CLI tokens present but no matching registry account; treating as signed-out"`, and return `false`. No use of `AccountIdentifier.cliFallbackAccountId(from:)` in this path; the registry is never mutated from here.
2. **Do NOT refresh, rotate, or write CLI tokens**: the existing `ClaudeCodeKeychainReader.loadTokens()` + `isAccessTokenFresh` calls are preserved verbatim. The expired-CLI branch is unchanged.
3. **Trace lines**: rename the successful-trace case to clarify it is the gated path (`"Restored authenticated state from fresh CLI session gated on registry match accountId=..."`). The refusal case gets a new trace line as above. The `count=0` canary in the mirror is addressed separately.

**File**: `Tempo macOS/AccountRegistryICloudMirror.swift`

**Function**: `writeIndex(accountIds:)` (private) and `writeMirror(for:)`

**Specific Changes** (approx. 25-35 LOC):

1. **Empty-write guard in `writeIndex`**: At the top of `writeIndex(accountIds:)`, when `accountIds.isEmpty`, read the current remote `index.json` at `TempoICloud.indexFileURL()`. If the file does not exist, OR if it decodes as `AccountsIndexFile` with `accountIds.isEmpty`, return early without writing and trace `"writeIndex no-op because registry empty and remote index is already empty or absent"`. If the remote file cannot be read or decoded, fall through to the normal write path (conservative: a single `count=0` write is acceptable if we cannot confirm the remote state).
2. **Preserve intentional clear**: When `accountIds.isEmpty` AND the remote index currently has `count >= 1`, the function proceeds through the normal write path. This is the `AccountRemovalService` last-account-removed path and must still flush.
3. **No change to `writeAccountMetadata`**: per the out-of-scope list, per-account `account.json` writes are untouched.
4. **No change to the public `writeMirror(for:)` API**: the guard is entirely inside `writeIndex`. Callers in `TempoMacApp` and `AccountRemovalService` do not need to know about it.

**File**: `Tempo macOS/TempoMacApp.swift`

**Functions**: `init(...)`, `onLaunch()`, `onAuthenticated()`

**Specific Changes** (approx. 10-15 LOC):

1. **Gate init-time seed**: Change `accountMirror.writeMirror(for: registry)` at the end of `init` to `if !registry.accounts.isEmpty { accountMirror.writeMirror(for: registry) }`. Rationale: at init, either the persisted `__registry__` slot hydrated one or more accounts (in which case we seed normally), or the registry is empty and there is nothing to seed. The empty-write guard in `writeIndex` is defense in depth; the caller-side guard removes the redundant call and keeps the trace log clean even across mirror-internal changes.
2. **Gate post-restore write in `onLaunch()`**: Change the call inside `if restored { ... accountMirror.writeMirror(for: registry) ... }` to only run when `!registry.accounts.isEmpty`. With the `tryRestoreSession` fix, `restored == true` implies the registry is non-empty, but the explicit guard documents the invariant and is cheap.
3. **`onAuthenticated()` is unchanged**: it runs only after `submitOAuthCode` added the account and set it active, so `registry.accounts` is non-empty by construction.

**File**: `Tempo macOS/DashboardPopoverView.swift`

**Specific Changes** (approx. 10-15 LOC):

1. **Gate the `Logout` row on registry**: Wrap the `Logout` `MenuActionRow` in `if !coordinator.registry.accounts.isEmpty { ... }`. Without this, the row's click handler is a no-op (because `registry.activeAccountId` is `nil`) and the row is misleading.
2. **Gate the usage content on registry**: In `contentState(use24HourTime:)`, add a leading branch: `if coordinator.registry.accounts.isEmpty { EmptyView() }` (or a compact placeholder matching the unauthenticated popover's visual). This prevents the `Fetching usage...` spinner from rendering when the invariant breaks.
3. **Do NOT change `SignInView`**: the outer `if coordinator.authState.isAuthenticated` gate in `SignInView` is preserved. Once the `tryRestoreSession` fix lands, the outer gate is sufficient for correctness; the popover-internal registry gates are pure defense in depth.
4. **Account row is unchanged**: it already renders "Not signed in" when `registry.accounts.isEmpty`, which is the correct behavior.

### Out of Scope

- Any change to `ClaudeCodeKeychainReader` semantics. It remains read-only.
- Any change to the Tempo web OAuth flow (`submitOAuthCode`, `exchangeCode`, `restoreAccount`, `refreshAccessToken`).
- Any change to `AccountRegistryICloudMirror.writeAccountMetadata` or to the per-account `account.json` writer. Only `writeIndex` gains an empty-write guard.
- Any change to iOS, watchOS, iOS widget, or watch widget behavior. The bug is macOS-only and the fix is macOS-only.
- Any migration support for users with existing CLI-only dev state. Per the multi-account-support change, CLI-only is no longer a sanctioned entry point; affected users will be prompted through Tempo OAuth on first launch after this fix.
- Any change to `AccountRemovalService`, `UsagePoller`, `UsageHistory`, `SessionEventWriter`, or widget snapshot writers.
- Any change to entitlements, Info.plist values, bundle identifiers, app groups, iCloud containers, or `.xcodeproj` settings.

## Testing Strategy

### Validation Approach

The testing strategy follows a two-phase approach: first, surface counterexamples that demonstrate the bug on unfixed code, then verify the fix works correctly and preserves existing behavior. Because the bug sits behind `tryRestoreSession()` and the macOS Keychain, tests use a fake `ClaudeCodeKeychainReader` seam and a fresh in-memory `AccountRegistry` to produce deterministic scenarios without touching the real Keychain.

### Exploratory Bug Condition Checking

**Goal**: Surface counterexamples that demonstrate the bug BEFORE implementing the fix. Confirm or refute the root cause analysis. If refuted, re-hypothesize before coding.

**Test Plan**: Construct a scenario with a fake `ClaudeCodeKeychainReader` that returns valid, fresh CLI tokens, a fresh empty `AccountRegistry`, and an empty `CredentialStore`. Invoke `tryRestoreSession()`. Assert `authState.isAuthenticated == true AND registry.accounts.isEmpty == true`. Independently, observe the `DevLog.trace` stream for `AccountMirror` writes and assert that `writeIndex wrote file path=... count=0` appears at least once during app init and once after `tryRestoreSession` returns. Run these assertions against the UNFIXED code to confirm the bug reproduces.

**Test Cases**:

1. **Fresh CLI-only launch**: empty registry + fresh CLI tokens + empty web credentials. Assert bug condition C(X) holds on unfixed code (will fail on fixed code, will pass on unfixed code).
2. **Expired CLI-only launch**: empty registry + expired CLI tokens. Assert bug condition does NOT hold on unfixed code (the expired branch already returns false). Used as a negative control.
3. **Init-time `count=0` canary**: fresh app init with empty registry. Assert at least one `writeIndex wrote file ... count=0` trace is emitted by `TempoMacApp.init`. Confirms the primary producer of the canary log line.
4. **Post-restore `count=0` canary**: CLI-only launch. Assert a second `writeIndex wrote file ... count=0` trace is emitted by the `onLaunch()` post-restore write. Confirms the secondary producer.
5. **Popover rendering under C(X)**: drive `SignInView` + `DashboardPopoverView` with `authState.isAuthenticated = true` and empty registry. Assert all three rendering defects are present simultaneously: "Not signed in" in the Account row, `Fetching usage...` in the body, and a `Logout` row. Confirms 1.2 and 1.5.

**Expected Counterexamples**:

- `tryRestoreSession()` returns `true` with empty registry on unfixed code.
- `writeIndex wrote file ... count=0` appears twice per CLI-only launch on unfixed code.
- Possible causes, in decreasing order of likelihood: (a) legacy CLI fallback branch, (b) unconditional init-time mirror seed, (c) post-restore mirror write assumes non-empty registry, (d) popover UI gated on `isAuthenticated` alone.

### Fix Checking

**Goal**: Verify that for all inputs where the bug condition holds on unfixed code, the fixed code produces the expected behavior.

**Pseudocode:**

```
FOR ALL launch_input WHERE isBugCondition(launch_input) holds on F DO
  state := runTryRestoreSession_fixed(launch_input)
  ASSERT state.authState.isAuthenticated == false
  ASSERT state.registry.accounts.isEmpty == true
  ASSERT state.authState.authSource == .none
END FOR
```

A fixed-version run is also required to confirm:

```
FOR ALL launch_input WHERE (registry seeded with a matching accountId for cliTokens.email) DO
  state := runTryRestoreSession_fixed(launch_input)
  ASSERT state.authState.isAuthenticated == true
  ASSERT state.authState.authSource == .cliSession
  ASSERT state.registry.activeAccountId IN state.registry.accounts.map { $0.accountId }
END FOR
```

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed function produces the same result as the original function.

**Pseudocode:**

```
FOR ALL launch_input WHERE NOT isBugCondition(launch_input) DO
  original := runTryRestoreSession_original(launch_input)
  fixed := runTryRestoreSession_fixed(launch_input)
  ASSERT original.authState == fixed.authState
  ASSERT original.registry.accounts == fixed.registry.accounts
  ASSERT original.registry.activeAccountId == fixed.registry.activeAccountId
END FOR

FOR ALL mirror_input WHERE registry.accounts.count >= 1 DO
  ASSERT writeIndex_original(mirror_input) writes equivalent bytes as writeIndex_fixed(mirror_input)
END FOR

FOR ALL mirror_input WHERE registry.accounts.isEmpty AND remote_index.count >= 1 DO
  ASSERT writeIndex_fixed(mirror_input) still writes count=0 exactly once (intentional clear)
END FOR
```

**Testing Approach**: Property-based testing is the right fit for preservation checking here because:

- The input domain (registry state cross CLI-token state cross web-credential state cross remote-index state) is large and combinatorial; manually enumerating unit cases misses edge states.
- Equivalence between original and fixed implementations can be asserted as a property over randomly generated inputs.
- The `DevLog.trace` stream is a deterministic observable, so write-thrash properties are checkable with a trace-capturing spy.

**Test Plan**: Observe behavior on UNFIXED code first for all non-C(X) inputs (mouse-driven sign-out, web OAuth restore, add-account, expired CLI tokens, launch with registry populated). Record the `authState`, registry, and `DevLog.trace` sequence. Then write property-based tests that re-run those inputs on fixed code and assert equivalence of observables.

**Test Cases**:

1. **Web-OAuth-only launch preservation**: launch with 1-3 registered accounts and valid web credentials, no CLI tokens. Observe that `tryRestoreSession` promotes the right account on unfixed code, then assert the same on fixed code.
2. **Registry-match CLI launch preservation**: launch with one registered account whose email matches the CLI profile, plus fresh CLI tokens. On unfixed code the CLI branch takes over after web restore fails; on fixed code the CLI branch takes over only when the email matches. Assert the authenticated outcome is the same.
3. **Intentional clear preservation**: start with one account, invoke `AccountRemovalService.removeAccount(accountId:)`. Assert `writeIndex wrote file ... count=0` is emitted exactly once, identical to unfixed behavior.
4. **Mirror idempotence**: call `writeMirror(for:)` N times with the same non-empty registry. Assert on-disk bytes are identical on fixed and unfixed code.
5. **Popover preservation for signed-in users**: render `DashboardPopoverView` with `authState.isAuthenticated == true` and `registry.accounts.count == 1`. Assert the popover renders the ring, chips, and `Logout` row exactly as on unfixed code.

### Unit Tests

- `tryRestoreSession` gated CLI branch: registry empty + fresh CLI tokens returns `false`, leaves `authState.isAuthenticated == false`.
- `tryRestoreSession` gated CLI branch: registry has matching accountId + fresh CLI tokens returns `true` with `.cliSession`, registry unchanged in membership but `activeAccountId` promoted.
- `tryRestoreSession` gated CLI branch: registry has non-matching accountId + fresh CLI tokens returns `false` unless some web credential also succeeded.
- `tryRestoreSession` expired CLI branch: returns `false` with `.none`, unchanged from original.
- `writeIndex` empty-write guard: empty registry + absent remote index returns without writing, no `count=0` trace.
- `writeIndex` empty-write guard: empty registry + remote `count=0` returns without writing.
- `writeIndex` empty-write guard: empty registry + remote `count=2` writes through once (intentional clear).
- `writeIndex` empty-write guard: empty registry + undecodable remote file falls through to normal write (conservative).
- `TempoMacApp.init` seeding guard: empty registry does not invoke `writeMirror`.
- `TempoMacApp.onLaunch` post-restore guard: `restored == true` with non-empty registry still calls `writeMirror`; `restored == true` with empty registry (defense against a future regression) does not.

### Property-Based Tests

- P1 over random registry + CLI + web inputs: `isAuthenticated == true` implies `registry.accounts.count >= 1`.
- P2 over random sequences of `writeMirror(for:)` calls against a simulated remote index: `count=0` is written at most once per contiguous empty-state interval.
- P3 over random launch inputs: count of CLI Keychain mutation calls (writes, deletes, rotations) equals zero. Enforce by routing CLI Keychain access exclusively through `ClaudeCodeKeychainReader`, whose test fake exposes a mutation counter that must stay at zero.
- P4 over random `(authState, registry)` cross product: rendering `DashboardPopoverView` with `registry.accounts.isEmpty == true` produces a view tree that contains no `Fetching usage` text, no `Logout` row, and no usage ring.

### Integration Tests

- Full CLI-only launch: empty persisted registry + valid CLI tokens, boot `TempoMacApp`, render popover, assert the popover is the coherent "Not Signed In" view, `index.json` is not touched on disk, no `count=0` trace in the boot log.
- CLI-then-OAuth flow: start from CLI-only launch (signed-out per fix), complete Tempo OAuth, assert `registry.accounts.count == 1`, popover flips to signed-in, `index.json` written once with `count=1`, `DevLog.trace` contains exactly one `writeIndex wrote file ... count=1` for this flow.
- Multi-account launch: persisted registry with 2 accounts, valid web credentials for both, boot, assert dashboard renders with active account selected, `index.json` written once with `count=2` at init, no extra writes.
- Last-account removal: start signed-in with 1 account, remove via `AccountRemovalService`, assert exactly one `writeIndex wrote file ... count=0` trace and that the popover returns to "Not Signed In".
- Regression canary: boot with empty registry and fresh CLI tokens (unfixed state simulated by temporarily skipping the `tryRestoreSession` guard in a DEBUG-only test). Assert the DEBUG runtime assertion (below) fires.

## Regression Canary

To prevent silent regression of the invariant `isAuthenticated == true implies registry.accounts.count >= 1`, add a lightweight DEBUG-only runtime assertion immediately after `tryRestoreSession()` returns in `MacOSAPIClient`:

```
#if DEBUG
if authState.isAuthenticated && registry.accounts.isEmpty {
    assertionFailure("cli-session-registry-consistency-fix regression: isAuthenticated with empty registry")
}
#endif
```

Additionally, treat the exact string `writeIndex wrote file path=.*/Tempo/accounts/index.json count=0` as a canary in the boot log. A post-fix verification script (or a manual observation step in the verification checklist) MUST confirm that no such line appears on launch when the user has NOT initiated a registry clear in that session. If the line appears, the bug has regressed or a new code path is writing `index.json` incorrectly.

Both signals are cheap: the runtime assertion is DEBUG-only, and the log-line check is passive. Neither is a release-build behavioral change. Together they give an immediate local signal (assertion) and a longer-running log signal (trace grep) for future regressions.
