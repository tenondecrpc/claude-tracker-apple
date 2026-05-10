# Implementation Plan

This plan implements the `cli-session-registry-consistency-fix` bugfix per `design.md`.
The fix has four scoped code changes plus a regression canary, sequenced so that the
exploration test in Task 1 demonstrates the bug condition `C(X)` on unfixed code,
Tasks 2-5 apply the fix in the order laid out by the design, and Task 6 flips the
exploration assertion and confirms the invariant `authState.isAuthenticated == true
implies AccountRegistry.accounts.count >= 1` on fixed code.

All requirement citations refer to `bugfix.md`. All design citations refer to
`design.md`.

- [ ] 1. Write bug condition exploration test (BEFORE any fix is applied)
  - **Property 1: Bug Condition** - CLI-only launch leaves registry empty while authenticated
  - **CRITICAL**: This fixture-based test MUST run against the UNFIXED code path and
    its assertion MUST encode `C(X)` as currently observable. On unfixed code the
    assertion PASSES, which confirms the bug exists. Task 6 flips the assertion
    after the fix lands so the same test PASSES for the post-fix invariant.
  - **GOAL**: Surface a concrete, reproducible counterexample for C(X):
    `authState.isAuthenticated == true AND AccountRegistry.accounts.isEmpty == true`
    after `tryRestoreSession()` returns on a machine with only Claude Code CLI
    credentials.
  - **Scoped PBT Approach**: C(X) here is deterministic given the four-tuple
    (registryAccounts, webCredentials, cliTokens, cliFresh). Scope the test to the
    concrete failing case: `registryAccounts = []`, `webCredentials = [:]`,
    `cliTokens` present, `isAccessTokenFresh == true`. A Swift `for` loop over a
    small domain of `cliTokens` seed values (e.g. three distinct refresh-token
    strings) gives reproducibility without the overhead of a full PBT harness.
  - Create a new standalone Swift tool at
    `tools/cli_session_registry_tests.swift` following the fixture-based pattern
    used by `tools/poller_orchestration_tests.swift` and
    `tools/multi_account_tests.swift`. Do NOT import `MacOSAPIClient`; its
    transitive deps (Security framework, WatchConnectivity, AppKit, iCloud) are
    not practical to link from a standalone `swiftc` tool.
  - Instead, replicate the CLI-fallback branch logic in a `FixtureRestoreSession`
    function that mirrors the unfixed control flow in
    `Tempo macOS/MacOSAPIClient.swift` `tryRestoreSession()`:
    1. Per-account web OAuth restore: iterate `webCredentials`, fail when empty.
    2. CLI fallback: call a `FixtureClaudeCodeKeychainReader` seam that returns
       the configured `cliTokens` and `isAccessTokenFresh` result.
    3. When CLI tokens are fresh, set
       `authState.isAuthenticated = true` and `authState.authSource = .cliSession`
       WITHOUT touching the `FixtureAccountRegistry`. This is the unfixed
       behavior we are capturing.
  - Define minimal fixture types inside the tool (`FixtureAuthState`,
    `FixtureAccountRegistry`, `FixtureCLITokens`, `FixtureCredentialStore`) with
    only the fields the exploration test reads. Match the naming style of
    `FixtureWorker` / `FixtureOrchestrator` in `tools/poller_orchestration_tests.swift`.
  - Add a `FixtureClaudeCodeKeychainReader` seam with a mutation counter
    (increments on any write, delete, or rotate). The counter is asserted in
    Task 7 (P3); for this task it exists but is not yet asserted.
  - Test case 1: `registryAccounts = []`, `webCredentials = [:]`,
    `cliTokens` present with fresh access token. Invoke `FixtureRestoreSession`.
    Assert (on unfixed behavior):
    `authState.isAuthenticated == true AND registry.accounts.isEmpty == true AND
    authState.authSource == .cliSession`.
  - Test case 2 (negative control): `registryAccounts = []`,
    `webCredentials = [:]`, `cliTokens` present with EXPIRED access token.
    Invoke `FixtureRestoreSession`. Assert:
    `authState.isAuthenticated == false AND authState.authSource == .none`.
    This proves the expired-CLI branch is not part of C(X) and must be preserved
    by the fix.
  - Print `CLI session registry tests: C(X) reproduced` on success. The tool must
    exit 0 when C(X) is observed on the unfixed fixture and exit non-zero
    otherwise, using the `SmokeFailure` pattern from the other `tools/` tests.
  - Run the tool with
    `swiftc -parse-as-library tools/cli_session_registry_tests.swift -o /tmp/cli_session_registry_tests && /tmp/cli_session_registry_tests`.
  - **EXPECTED OUTCOME**: Tool exits 0, prints `C(X) reproduced`. This confirms
    the bug condition is reachable on the fixture that mirrors the unfixed code.
  - Document the observed counterexample in a comment at the top of the tool
    (e.g. `// Counterexample: registryAccounts=[], webCredentials=[:], cliTokens=fresh -> isAuthenticated=true, registry.accounts.isEmpty=true`).
  - _Requirements: 1.1, 1.2 (bugfix.md)_
  - _Design: Bug Condition section, Exploratory Bug Condition Checking test cases 1-2 (design.md)_

- [ ] 2. Apply fix change 1 of 4 - Gate CLI fallback in `tryRestoreSession()` on registry membership
  - Edit `Tempo macOS/MacOSAPIClient.swift`, function `tryRestoreSession()`,
    the CLI fallback block at approximately lines 364-378 (the block that sets
    `authState.isAuthenticated = true` with `.cliSession`).
  - Before setting `isAuthenticated = true`, load the CLI profile email via
    `DetectedClaudeAccount.load()` and canonicalize it with
    `AccountIdentifier.canonicalize(email:)`. Wrap in a `do/catch`; treat
    `AccountIdentifierError.emptyEmail` as "no matching registry account".
  - Branch on whether the canonical accountId is present in
    `registry.accounts.map { $0.accountId }`:
    - If present: promote that accountId to `registry.activeAccountId` if not
      already active, set `authState.isAuthenticated = true`,
      `authState.authSource = .cliSession`, and return `true`. Do NOT mutate
      `registry.accounts` membership. Do NOT call
      `AccountIdentifier.cliFallbackAccountId(from:)` on this path.
    - If absent: leave `authState.isAuthenticated = false`,
      `authState.authSource = .none`, emit
      `DevLog.trace("CLI tokens present but no matching registry account; treating as signed-out")`,
      and return `false`.
  - Rename the successful-path trace to
    `"Restored authenticated state from fresh CLI session gated on registry match accountId=<canonicalId>"`
    so the gated path is greppable.
  - Do NOT refresh, rotate, or write CLI tokens. The existing
    `ClaudeCodeKeychainReader.loadTokens()` and `isAccessTokenFresh(_:)` calls
    are preserved verbatim.
  - The expired-CLI branch (where `isAccessTokenFresh(_:)` returns `false`) is
    unchanged: it already returns `false` with `.none`.
  - Immediately after the function returns in its caller (or as the last
    statement in `tryRestoreSession` before returning the final boolean), add
    the DEBUG-only regression canary from the design:
    ```
    #if DEBUG
    if authState.isAuthenticated && registry.accounts.isEmpty {
        assertionFailure("cli-session-registry-consistency-fix regression: isAuthenticated with empty registry")
    }
    #endif
    ```
    Place it in `MacOSAPIClient.swift`, not in a caller, so the invariant is
    enforced at the source of truth.
  - _Bug_Condition: `isBugCondition(input)` where `registryAccounts = []`, `webCredentials = [:]`, `cliTokens` present and fresh (design.md Bug Condition)_
  - _Expected_Behavior: `authState.isAuthenticated == true` implies `registry.accounts.count >= 1` after `tryRestoreSession()` returns (design.md Property 1)_
  - _Preservation: `ClaudeCodeKeychainReader` remains read-only (design.md Property 3); expired-CLI branch unchanged (design.md Preservation Requirements)_
  - _Requirements: 2.1, 2.2, 2.5, 2.6, 2.7, 3.2, 3.3 (bugfix.md)_
  - _Design: Fix Implementation change 1, Property 1, Property 3, Regression Canary (design.md)_

- [ ] 3. Apply fix change 2 of 4 - Add empty-write guard to `AccountRegistryICloudMirror.writeIndex(accountIds:)`
  - Edit `Tempo macOS/AccountRegistryICloudMirror.swift`, private function
    `writeIndex(accountIds:)`.
  - At the top of the function, when `accountIds.isEmpty`, read the current
    remote `index.json` at `TempoICloud.indexFileURL()` using `Data(contentsOf:)`
    and `JSONDecoder().decode(AccountsIndexFile.self, from:)`. Handle the three
    cases per the design:
    - Remote file absent (`FileManager.default.fileExists(atPath:) == false` or
      `Data(contentsOf:)` throws a file-not-found error): return early without
      writing. Emit
      `DevLog.trace("writeIndex no-op because registry empty and remote index is absent")`.
    - Remote file present and decodes to `AccountsIndexFile` with
      `accountIds.isEmpty == true` (remote `count == 0`): return early without
      writing. Emit
      `DevLog.trace("writeIndex no-op because registry empty and remote index is already count=0")`.
    - Remote file present and decodes to `AccountsIndexFile` with
      `accountIds.count >= 1`: fall through to the normal write path. This is the
      intentional last-account-removal flush via `AccountRemovalService` and must
      still write `count=0` exactly once.
    - Remote file present but undecodable (corrupt JSON, unknown schema, I/O
      error other than not-found): fall through to the normal write path. This
      is the conservative branch; a single `count=0` write is acceptable when
      the remote state cannot be confirmed.
  - Do NOT change the normal (`accountIds.count >= 1`) write path. The existing
    `DevLog.trace("writeIndex wrote file path=... count=N")` emission for
    `N >= 1` is preserved verbatim.
  - Do NOT change `writeAccountMetadata` or any other public API on the mirror.
    The guard is entirely inside `writeIndex`.
  - Do NOT change the public `writeMirror(for:)` signature or call sites.
  - _Bug_Condition: `writeIndex wrote file ... count=0` canary trace on CLI-only launch (design.md Hypothesized Root Cause items 2 and 3)_
  - _Expected_Behavior: `count=0` is written at most once per contiguous empty-state interval (design.md Property 2)_
  - _Preservation: intentional last-account clears still flush `count=0` exactly once; `writeAccountMetadata` unchanged (design.md Preservation Requirements)_
  - _Requirements: 2.3, 2.4, 3.6 (bugfix.md)_
  - _Design: Fix Implementation change 2, Property 2 (design.md)_

- [ ] 4. Apply fix change 3 of 4 - Gate coordinator-level mirror writes in `TempoMacApp`
  - Edit `Tempo macOS/TempoMacApp.swift`.
  - In `init(...)`, locate the trailing
    `accountMirror.writeMirror(for: registry)` call (the init-time seed).
    Replace it with:
    ```
    if !registry.accounts.isEmpty {
        accountMirror.writeMirror(for: registry)
    }
    ```
  - In `onLaunch()`, locate the block gated on
    `if restored { ... accountMirror.writeMirror(for: registry) ... }`. Wrap
    only the `writeMirror` call in an additional
    `if !registry.accounts.isEmpty { ... }` guard so the write runs only when a
    registry account was actually promoted.
  - Do NOT change `onAuthenticated()`. It runs only after `submitOAuthCode`
    added the account and set it active, so `registry.accounts` is non-empty by
    construction.
  - Do NOT move the guards into `writeMirror(for:)` itself. The caller-side
    guard documents the invariant at the call site and keeps the trace log
    clean even if a future change loosens the mirror-internal guard added in
    Task 3. Both guards are intentional defense in depth.
  - _Bug_Condition: `TempoMacApp.init` and `onLaunch()` invoke `writeMirror` on an empty registry, producing `count=0` thrash (design.md Hypothesized Root Cause items 2 and 3)_
  - _Expected_Behavior: `writeMirror` is not invoked when `registry.accounts.isEmpty` (design.md Fix Implementation change 3)_
  - _Preservation: `onAuthenticated()` unchanged; non-empty registry still seeds iCloud on init (design.md Preservation Requirements)_
  - _Requirements: 2.3, 2.4, 3.6, 3.7 (bugfix.md)_
  - _Design: Fix Implementation change 3 (design.md)_

- [ ] 5. Apply fix change 4 of 4 - Defense-in-depth UI gating in `DashboardPopoverView`
  - Edit `Tempo macOS/DashboardPopoverView.swift`.
  - Wrap the `Logout` `MenuActionRow` in
    `if !coordinator.registry.accounts.isEmpty { ... }`. Without this, the
    row's click handler is a no-op when `registry.activeAccountId == nil` and
    the row is misleading.
  - In `contentState(use24HourTime:)` (or the equivalent body builder that
    renders the usage ring, burn-rate chips, and `Fetching usage...`
    placeholder), add a leading branch:
    `if coordinator.registry.accounts.isEmpty { return /* compact placeholder matching the signed-out popover */ }`.
    Prefer returning the same view shape as the outer unauthenticated popover
    in `SignInView` rather than `EmptyView()` so the popover has a coherent
    fallback if the invariant ever breaks again.
  - Do NOT change the outer
    `if coordinator.authState.isAuthenticated` gate in `SignInView`. Once
    Task 2 lands, the outer gate is sufficient for correctness on real runs;
    the popover-internal registry gates are pure defense in depth.
  - Do NOT change the Account row. It already renders "Not signed in" when
    `registry.accounts.isEmpty`, which is the correct behavior.
  - _Bug_Condition: popover renders "Not signed in" + "Fetching usage..." + `Logout` row simultaneously when `authState.isAuthenticated == true AND registry.accounts.isEmpty == true` (bugfix.md 1.2, 1.5)_
  - _Expected_Behavior: no `Fetching usage` text, no `Logout` row, no usage ring when `registry.accounts.isEmpty` (design.md Property 4)_
  - _Preservation: signed-in users with `registry.accounts.count >= 1` see the unchanged popover (design.md Preservation Requirements)_
  - _Requirements: 2.5, 2.6, 1.2, 1.5 (bugfix.md)_
  - _Design: Fix Implementation change 4, Property 4 (design.md)_

- [ ] 6. Flip exploration test assertion and verify the post-fix invariant
  - **Property 1: Expected Behavior** - CLI-only launch without a matching registry account stays signed-out
  - **IMPORTANT**: Edit the SAME test in `tools/cli_session_registry_tests.swift`
    written in Task 1. Do NOT write a new test. This preserves the
    exploration-to-validation pairing the bugfix workflow relies on.
  - Update `FixtureRestoreSession` to mirror the POST-FIX control flow from
    Task 2: the CLI fallback branch now resolves the CLI email through
    `AccountIdentifier.canonicalize(email:)` and only sets
    `isAuthenticated = true` when the canonical id is in `registry.accounts`.
    Otherwise it sets `isAuthenticated = false` and `authSource = .none`.
  - Flip the test case 1 assertion from
    `isAuthenticated == true AND registry.accounts.isEmpty == true` to
    `isAuthenticated == false AND registry.accounts.isEmpty == true AND authSource == .none`.
  - Keep test case 2 (expired-CLI negative control) unchanged; it must still pass.
  - Add a new test case 3 that seeds the registry with one account whose
    canonical email matches the CLI profile, plus fresh CLI tokens. Assert
    `isAuthenticated == true AND authSource == .cliSession AND registry.activeAccountId` is set
    to that account's id AND `registry.accounts.count == 1` (membership unchanged).
    This covers the registry-match branch from Task 2.
  - Rebuild and run the tool:
    `swiftc -parse-as-library tools/cli_session_registry_tests.swift -o /tmp/cli_session_registry_tests && /tmp/cli_session_registry_tests`.
  - **EXPECTED OUTCOME**: All three test cases pass. Tool exits 0 and prints
    `CLI session registry tests passed` (adjust the success banner to match the
    post-fix semantics; the Task 1 `C(X) reproduced` banner is no longer
    accurate).
  - _Requirements: 2.1, 2.2, 2.5, 2.6 (bugfix.md)_
  - _Design: Property 1, Fix Checking section (design.md)_

- [ ] 7. Add follow-up property tests for P2, P3, P4 and the mirror unit cases
  - Extend `tools/cli_session_registry_tests.swift` (or add separate test
    functions within the same tool) to cover the remaining properties and unit
    cases from `design.md` Testing Strategy. A single tool is preferred over
    fragmenting into multiple tools so the CI invocation in Task 8 stays a
    single `swiftc` + run step.
  - **Property 2: Preservation** - Non-thrashing empty index writes
    - Build a `FixtureMirror` fixture that mirrors the
      `AccountRegistryICloudMirror.writeIndex(accountIds:)` control flow from
      Task 3 against an in-memory `remoteIndex: [String]?` (nil = absent,
      `[]` = `count=0`, `["a"]` = `count=1`).
    - Unit case A: empty `accountIds` + `remoteIndex == nil` - no write,
      `remoteIndex` stays nil, no `count=0` trace emitted.
    - Unit case B: empty `accountIds` + `remoteIndex == []` - no write.
    - Unit case C: empty `accountIds` + `remoteIndex == ["a", "b"]` - writes
      through exactly once, `remoteIndex` becomes `[]`, exactly one `count=0`
      trace emitted.
    - Unit case D: empty `accountIds` + undecodable remote (simulate by
      injecting a `FixtureMirror.readError`) - writes through exactly once
      (conservative fallback).
    - Unit case E: non-empty `accountIds` + any `remoteIndex` state - writes
      through, exactly one `count=N` trace with `N >= 1`.
    - Property P2 loop: over a deterministic sequence of 50 alternating empty
      and non-empty `writeMirror(for:)` calls, assert `count=0` is written at
      most once per contiguous empty-state interval.
  - **Property 3: Preservation** - CLI Keychain read-only
    - The `FixtureClaudeCodeKeychainReader` seam from Task 1 already exposes a
      mutation counter. Over all fixture runs across test cases 1, 2, and 3
      from Task 6 plus the P2 sequences above, assert the aggregate mutation
      counter is exactly 0 at the end of the tool.
  - **Property 4: Preservation** - Popover coherence invariant
    - Popover view-tree introspection is not feasible from a standalone
      `swiftc` tool. Encode P4 as a logical assertion on a
      `FixturePopoverState` record that mirrors the gating logic added to
      `DashboardPopoverView` in Task 5: inputs are `(isAuthenticated: Bool,
      registryEmpty: Bool)`; outputs are three booleans
      `rendersFetchingUsage`, `rendersLogoutRow`, `rendersUsageRing`. Implement
      `FixturePopoverState.from(authState:registry:)` to match the view
      conditions exactly (must cite
      `DashboardPopoverView.swift` line numbers in a comment).
    - Loop over the 4-case cross product of `(isAuthenticated,
      registryEmpty)`. Assert that whenever `registryEmpty == true`, all three
      booleans are false, regardless of `isAuthenticated`.
  - Print a distinct success banner per property block for readability (e.g.
    `P2 passed`, `P3 passed`, `P4 passed`). The tool's final exit 0 and
    `CLI session registry tests passed` banner from Task 6 remains the overall
    pass signal.
  - Rebuild and run:
    `swiftc -parse-as-library tools/cli_session_registry_tests.swift -o /tmp/cli_session_registry_tests && /tmp/cli_session_registry_tests`.
  - **EXPECTED OUTCOME**: All property and unit cases pass.
  - _Requirements: 2.3, 2.4, 2.7, 3.2, 3.6 (bugfix.md); Property 4 also validates 1.2 and 1.5_
  - _Design: Property 2, Property 3, Property 4, Unit Tests section (design.md)_

- [ ] 8. Build both schemes with `xcodebuild` and run the widget smoke test
  - Run
    `xcodebuild -project Tempo.xcodeproj -scheme "Tempo macOS" -destination "generic/platform=macOS" -configuration Debug build`
    from the repo root. Expect a clean build with no errors on any target
    (`Tempo macOS` plus `Tempo macOS Widget` extension).
  - Run
    `xcodebuild -project Tempo.xcodeproj -scheme "Tempo" -destination "generic/platform=iOS" -configuration Debug build`
    from the repo root. Expect a clean build. This confirms the macOS-only fix
    did not accidentally break any `Shared/` contract that iOS depends on
    (`AccountIdentifier`, `AccountsIndexFile`, `TempoICloud.indexFileURL()`).
  - Build and run the widget smoke test:
    `swiftc -parse-as-library tools/widget_smoke_test.swift -o /tmp/widget_smoke_test && /tmp/widget_smoke_test`.
    Expect exit 0. This matches the approach referenced in the
    `multi-account-support` 9.7 task.
  - If either `xcodebuild` run fails, stop and escalate; do not paper over
    compile errors by editing outside the four files from Tasks 2-5.
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8 (bugfix.md, regression prevention across all unchanged behaviors)_
  - _Design: Integration Tests section (design.md)_

- [ ] 9. Manual verification on a CLI-only machine and checklist file
  - Create `.kiro/specs/cli-session-registry-consistency-fix/manual-verification.md`
    with a numbered checklist covering the following scenarios. Each item must
    include exact commands, exact expected UI state, and the exact log strings
    to grep for.
  - Scenario A (the bug): on a machine where the user has ONLY Claude Code CLI
    credentials (no Tempo OAuth accounts persisted in the `__registry__`
    Keychain slot), launch `Tempo macOS` from Xcode with Debug logging enabled.
    Open the menu bar popover. Confirm:
    - Account row reads "Not Signed In" (or equivalent).
    - Body renders the coherent signed-out view, NOT the "Fetching usage..."
      spinner.
    - No `Logout` action row is visible.
    - The DEBUG `assertionFailure` from Task 2 does NOT fire. Run the app in
      a Debug scheme so the assertion is live.
    - `log show --predicate 'subsystem == "com.tenondev.tempo"' --last 1m`
      (or the equivalent trace output from stderr when running from Xcode)
      does NOT contain any line matching
      `writeIndex wrote file path=.*Tempo/accounts/index.json count=0` during
      app launch.
  - Scenario B (CLI-then-OAuth flow): from the Scenario A state, click the
    Tempo OAuth sign-in affordance and complete the OAuth flow. Confirm:
    - Popover flips to the normal signed-in view (account name, ring,
      burn-rate chips, `Logout` row).
    - `Tempo/accounts/index.json` in the iCloud container is written exactly
      once with `count=1`. Verify via
      `cat "$HOME/Library/Mobile Documents/iCloud~com~tenondev~tempo~claude/Documents/Tempo/accounts/index.json"`
      and via exactly one
      `writeIndex wrote file path=... count=1`
      trace in the log.
    - `registry.accounts.count == 1` and `registry.activeAccountId` is set to
      the newly added account.
  - Scenario C (intentional last-account removal still flushes): from Scenario
    B, click `Logout` (or invoke `AccountRemovalService.removeAccount` for the
    sole account). Confirm:
    - `Tempo/accounts/index.json` is rewritten exactly once with `count=0`.
    - The log contains exactly one new `writeIndex wrote file ... count=0`
      trace, attributable to the removal flow and not to a launch-time write.
    - Popover returns to the coherent "Not Signed In" view.
  - Scenario D (multi-account regression check): if a second test account is
    available, add it via the add-account flow. Confirm
    `index.json` is written exactly once with `count=2`, and the popover
    renders the active account correctly. No extra `count=0` or `count=1`
    writes appear in the trace during steady state.
  - Each scenario entry must include a final "Pass / Fail" checkbox and a
    free-text Notes field for the verifier.
  - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 3.6, 3.7 (bugfix.md)_
  - _Design: Integration Tests section, Regression Canary (design.md)_

- [ ] 10. Update `docs/PLAN.md` and `docs/CONVENTIONS.md`
  - Edit `docs/PLAN.md` under the `### Multi-account support` block (around the
    "Status: Complete" line): append a single bullet under "Scope delivered"
    (or immediately after it) noting that the
    `cli-session-registry-consistency-fix` bugfix shipped to restore the
    invariant that `authState.isAuthenticated == true` implies
    `AccountRegistry.accounts.count >= 1`, gate `writeIndex` against empty
    thrash, and add defense-in-depth popover gating. Keep the note to two
    sentences max. Use ASCII hyphens only.
  - Edit `docs/CONVENTIONS.md` under `## Multi-Account`: clarify the CLI
    contract. Append a short subsection (or bullet under "Registry Ownership")
    stating:
    - CLI-only credentials are NOT a sanctioned sign-in path on macOS.
    - `ClaudeCodeKeychainReader` remains the only CLI-token reader and is
      strictly read-only.
    - `MacOSAPIClient.tryRestoreSession()` only promotes a CLI session to
      `isAuthenticated == true` when the canonical CLI email resolves to an
      accountId already present in `AccountRegistry`; otherwise the app
      presents the signed-out popover and the user is expected to complete
      Tempo OAuth.
  - Do NOT edit any other section of either document. Do NOT introduce em or
    en dashes. Do NOT add non-ASCII punctuation.
  - After editing, verify both files render correctly (no broken markdown
    tables or headings) by reading them back and visually scanning the diff.
  - _Requirements: 3.3, 3.8 (bugfix.md, documentation preservation of invariants)_
  - _Design: Overview paragraph on "CLI-only is not a sanctioned entry point" (design.md)_

## Task Dependency Graph

```
  Task 1 (exploration test on unfixed code, asserts C(X) holds)
    |
    v
  Task 2 (fix: gate CLI fallback in tryRestoreSession + DEBUG canary)
    |
    +--> Task 3 (fix: empty-write guard in writeIndex)   [independent of Task 2 at the file level; safe to land in parallel]
    |        |
    +--> Task 4 (fix: gate TempoMacApp init + onLaunch writes)   [depends conceptually on Task 3; caller-side guard]
    |        |
    +--> Task 5 (fix: defense-in-depth UI gating in DashboardPopoverView)   [independent of Tasks 3 and 4]
    |        |
    v        v
  Task 6 (flip exploration assertion, confirm post-fix invariant)
    |
    v
  Task 7 (add P2, P3, P4 property tests + unit cases in same tool)
    |
    v
  Task 8 (xcodebuild Tempo macOS + Tempo, run widget smoke test)
    |
    v
  Task 9 (manual verification on CLI-only machine + checklist file)
    |
    v
  Task 10 (docs update: PLAN.md + CONVENTIONS.md)
```

Notes on concurrency:

- Tasks 2, 3, 4, 5 touch four different files and have no direct code
  dependencies, so a reviewer can land them as separate commits in any order
  as long as all four merge before Task 6 runs. Task 2 is listed first because
  it is the primary fix; Task 3 is the primary producer of the `count=0`
  canary; Task 4 is the caller-side defense; Task 5 is UI-only defense in
  depth.
- Task 6 is a hard gate: it must run only after Tasks 2-5 are all applied,
  because its assertion encodes the full post-fix behavior.
- Task 7 depends on Task 6 (the fixture control flow updated in Task 6 is
  reused for the P2/P3/P4 cases).
- Task 8 is the compile-and-smoke gate. It must precede Task 9 so manual
  verification runs against a build that is known to compile cleanly on both
  macOS and iOS targets.
- Task 10 is the last step and must not be started before Task 9 passes, so
  the PLAN.md "shipped" note is accurate.
