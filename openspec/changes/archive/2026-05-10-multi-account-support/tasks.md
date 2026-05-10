## 1. Shared models and contracts

- [x] 1.1 Add `Account` value type in `Shared/` (accountId, email, displayName, createdAt) with `Codable`, `Identifiable`, `Equatable` conformance and `accountId`-based equality
- [x] 1.2 Add an `AccountIdentifier` canonicalizer in `Shared/` that normalizes email to the canonical `accountId` (NFC, trim, lowercase) and rejects empty input
- [x] 1.3 Extend `UsageState` in `Shared/Models.swift` with `accountId: String` (required; decoding with no accountId throws)
- [x] 1.4 Extend `SessionInfo` and `LocalProjectStat` with `accountId: String`, defaulting to `"unassigned"` when unknown; update mock fixtures
- [x] 1.5 Update `WidgetUsageSnapshot` to include `accountId: String` and `accountLabel: String` as first-class fields; no support for older schema versions
- [x] 1.6 Extend `Shared/TempoICloud.swift` with helpers: `accountsDirectoryURL()`, `accountDirectoryURL(for:)`, `indexFileURL()`, `usageFileURL(for:)`, `usageHistoryFileURL(for:)`, `latestSessionFileURL(for:)`, `accountMetadataFileURL(for:)` (with percent-encoding for unsafe chars)
- [x] 1.7 Confirm `AlertPreferencesSync` and appearance-mode sync still target `Tempo/` root (no per-account split)

## 2. macOS Keychain and registry

- [x] 2.1 Rework `Tempo macOS/CredentialStore.swift` to store credentials under `kSecAttrService = "com.tenondev.tempo.claude.oauth"` keyed by accountId; add `save(_:for:)`, `load(for:)`, `delete(for:)`, `knownAccountIds()`; remove the fixed `credentials` slot
- [x] 2.2 Implement `AccountRegistry` (`@Observable @MainActor final class`) in `Tempo macOS/` with `accounts`, `activeAccountId`, `add`, `remove`, `rename`, `setActive`, persisted via the `__registry__` Keychain slot and `UserDefaults` for active account
- [x] 2.3 Implement registry iCloud mirror writer: `Tempo/accounts/<id>/account.json` and `Tempo/accounts/index.json` with no secret fields
- [x] 2.4 One-shot startup cleanup: delete the legacy `credentials` Keychain slot and `~/.config/tempo-for-claude/credentials.json` if present; do not read their contents
- [x] 2.5 Account removal deletes the per-account Keychain credential slot and the iCloud `Tempo/accounts/<id>/` directory (no retired copy)

## 3. macOS auth, polling, and writers

- [x] 3.1 Update `MacOSAPIClient` so `signIn` always adds a new account (or updates tokens for an existing accountId) and `signOut(for:)` scopes to a specific accountId
- [x] 3.2 Refactor `UsagePoller` into an orchestrator plus `AccountPollingWorker` per account with independent 15-minute schedules, backoff state, and `latestUsage` snapshots
- [x] 3.3 Wire token refresh in each worker to rewrite only its own Keychain slot and never the Claude Code CLI slot
- [x] 3.4 Update `UsageHistory` to maintain per-account append/merge/dedupe and write to per-account iCloud paths; stop writing to `Tempo/usage-history.json`
- [x] 3.5 Update `ClaudeLocalDBReader` and `SessionEventWriter` to tag sessions with `accountId` from `~/.claude.json` email match or `"unassigned"`; write to per-account `latest.json` or the `accounts/unassigned/latest.json` bucket
- [x] 3.6 Update `MacAppCoordinator` to own `AccountRegistry`, start the per-account polling workers, and publish per-account widget snapshots on poll success
- [x] 3.7 Remove any code paths that read or write the legacy flat `Tempo/usage.json`, `Tempo/usage-history.json`, or `Tempo/latest.json`

## 4. macOS UI

- [x] 4.1 Add an Account row at the top of the menu bar popover (label + switcher menu with `Set as active`, `Add account`, `Manage accounts`)
- [x] 4.2 Update Welcome window for add-account mode with distinct header and cancel; ensure initial sign-in also sets the new account as active
- [x] 4.3 Add an Accounts pane in Preferences listing label, email, createdAt, last poll, last session, and per-row sign-out; include "Add account" footer
- [x] 4.4 Make the Detail window bind to `activeAccountId`; reload usage, history, sessions, and projects when the active account changes; show account label in header
- [x] 4.5 Handle active-account reassignment when the active account is signed out (pick first remaining or clear)

## 5. iOS reader and relay

- [x] 5.1 Update `iCloudUsageReader` to watch the per-account tree via `NSMetadataQuery`, read `Tempo/accounts/index.json`, and maintain a `[String: UsageState]` in-memory map
- [x] 5.2 Remove any code that observes or reads the flat `Tempo/usage.json` / `Tempo/latest.json` paths
- [x] 5.3 Persist iOS `activeAccountId` in `UserDefaults` and propagate changes through the iOS coordinator; default to the first discovered account
- [x] 5.4 Rework `WatchRelayManager` to send active-account `UsageState` via `updateApplicationContext` (with `accountId`, `accountLabel`) and send `"NoActiveAccount"` when empty
- [x] 5.5 Update `WatchRelayManager` to send `SessionInfo` via `transferUserInfo` with `accountId`; gate completion delivery to sessions whose accountId equals iOS `activeAccountId`
- [x] 5.6 Update iOS widget snapshot writer to maintain per-account snapshots in shared App Group storage, update active-account pointer, and reload widgets on active-account change

## 6. iOS UI

- [x] 6.1 Add an account chip in the dashboard header with active account label; tap opens an Accounts sheet
- [x] 6.2 Build the Accounts sheet listing discovered accounts, last-updated time, active marker, "Set as active" action, and "Add an account - use Mac app" footer
- [x] 6.3 Filter Activity and Session detail views by `activeAccountId`
- [x] 6.4 Render a "CLI-only sessions" group (unassigned bucket) and include a macOS-only "Associate with account" affordance that explains availability on iOS

## 7. watchOS

- [x] 7.1 Rework `WatchSessionReceiver` to handle `didReceiveApplicationContext` for `UsageState` and `NoActiveAccount` payloads; dispatch to main actor
- [x] 7.2 Update `TokenStore` on watch to track `activeAccountId`, `accountLabel`, and drop stale `pendingCompletion` when `accountId` changes
- [x] 7.3 Update the watch dashboard header to show `accountLabel`; add tap-to-show-full sheet; add "No accounts available" state
- [x] 7.4 Ensure `CompletionView` shows the `accountLabel` and that receiver ignores `SessionInfo` payloads with mismatched accountId

## 8. Widgets

- [x] 8.1 Update snapshot writers on iOS and macOS to write per-account snapshots and maintain an `activeAccountId` pointer entry
- [x] 8.2 Add `SelectAccountIntent` on iOS and macOS widgets (dynamic options sourced from `Tempo/accounts/index.json` plus "Active account"); wire the provider to load the correct per-account snapshot
- [x] 8.3 Implement fallback-to-active-account behavior with "account removed" indicator when a configured account vanishes
- [x] 8.4 Update widget deep-link routes to set the iOS active account and target the correct macOS detail window
- [x] 8.5 Confirm watch widget stays on the iPhone's active account only and has no account intent

## 9. Testing and verification

- [x] 9.1 Extend `tools/widget_smoke_test.swift` to cover multi-account snapshots and `AccountIntent` placeholder rendering
- [x] 9.2 Add unit tests for `AccountIdentifier` canonicalization, `Account` equality, and per-account `UsageState` decoding
- [x] 9.3 Add unit tests for per-account `UsagePoller` orchestration (isolation of backoff and refresh across accounts)
- [x] 9.4 Manual verification: add two accounts, switch active account, sign out of active account, confirm per-account Keychain slots and iCloud directories
- [x] 9.5 Manual verification: iOS discovery via iCloud, account chip switching, Activity filtering, widget with pinned account
- [x] 9.6 Manual verification: watch follows iPhone active account, clears on `NoActiveAccount`, completion alert suppression for non-active account
- [x] 9.7 Build `Tempo macOS` and `Tempo` schemes via `xcodebuild` and run the repo widget smoke test

## 10. Docs

- [x] 10.1 Update `docs/CONVENTIONS.md` with the multi-account layout, accountId rules, and registry ownership
- [x] 10.2 Update `docs/PLAN.md` to reflect multi-account support delivery (no migration milestone)
- [x] 10.3 Add a README section on multi-account: adding, switching, and signing out per account, watch behavior
- [x] 10.4 Note in the README developer/testing section that any leftover `Tempo/usage.json`, `Tempo/usage-history.json`, or `Tempo/latest.json` in iCloud from prior dev builds can be deleted by hand
