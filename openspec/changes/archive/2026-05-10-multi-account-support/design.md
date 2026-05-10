## Context

Tempo is pre-release. The macOS app currently stores one OAuth credential blob under Keychain service `com.tenondev.tempo.claude.oauth` / account `credentials`, polls `/api/oauth/usage` on a single schedule, and writes one `usage.json` / `usage-history.json` into the iCloud `Tempo/` folder. Local Claude Code session ingestion from `~/.claude/` is similarly singular and produces one `latest.json` relay. The iOS app reads those files, relays a single `UsageState` and optional `SessionInfo` to the watch, and writes a single widget snapshot per platform. Watch and widgets render that one payload.

Because there are no production users yet, we replace the single-account contract outright instead of layering a migration on top of it. The multi-account tree becomes the one-and-only layout. Any stale files left behind from prior dev builds are acceptable collateral and can be cleaned up manually.

Constraints carried from `AGENTS.md`:
- OAuth credentials never leave macOS (no iCloud, no widget storage, no UserDefaults). Keychain is the only home.
- Watch relay and haptic logic must not move into `Shared/`.
- `Shared/TempoICloud.swift` is a contract point; path changes are high-risk even though no migration is required.
- Distinction between `updateApplicationContext` and `transferUserInfo` on WatchConnectivity must be preserved.

Stakeholders: macOS app owner (pipelines, widgets), iOS app (dashboard, relay, widgets), watch (dashboard, session alerts).

## Goals / Non-Goals

**Goals:**
- Make the account email the user-facing identifier for each account (accountId = canonicalized email).
- Support sign-in for multiple Anthropic OAuth accounts simultaneously on macOS with isolated Keychain storage per account.
- Partition iCloud, widget, and WatchConnectivity payloads per accountId using one consistent layout.
- Provide account navigation on macOS and iOS dashboards, plus account-aware session detail views.
- Keep watchOS strictly downstream: the watch follows the iPhone's currently active account and does not persist its own selection.

**Non-Goals:**
- Any migration, promotion, or import of the previous single-account layout. There are no active users, so backwards compatibility is not provided.
- Legacy fallback readers. If `Tempo/accounts/` is missing, Tempo shows empty state; it does not read the old flat files.
- Per-account alert preferences or appearance mode (stays global for this change).
- Per-account macOS polling cadence overrides.
- Multi-account support inside the Claude Code CLI itself or reading more than one CLI profile. If a user has multiple CLI identities on disk, Tempo associates sessions to accounts via email-matching on the `oauthAccount` data it already reads.
- Merging or cross-account analytics (no "combined usage" views).
- Changing the Anthropic OAuth client ID, redirect URI, or scopes.

## Decisions

### accountId derivation
- accountId is the lowercased, trimmed, NFC-normalized email address returned by the OAuth profile (`oauthAccount.emailAddress`). The canonicalized form is reused verbatim for Keychain `kSecAttrAccount` values and for the iCloud directory name. File-system escaping only affects characters outside `[a-z0-9._@-]`, which are percent-encoded in the directory name while the in-memory `accountId` stays canonical.
- Why email: it is what the user recognizes, it is already surfaced by the existing `DetectedClaudeAccount` reader, and it is stable across refresh-token rotations. Alternatives considered: opaque UUID per sign-in (loses the "identify by email" requirement), Anthropic's internal account id (not reliably exposed on the usage endpoint).
- If the OAuth profile does not return an email (legacy CLI-only fallback path), a synthetic accountId `cli-local-<shortHash>` is used and clearly labeled in the UI as "Unknown account". The user can rename the display label; accountId itself is immutable.

### Account registry lives on macOS; iOS reads it
- macOS is the sign-in authority. It owns a new `AccountRegistry` (a `@Observable @MainActor` type in `Tempo macOS/`) that serializes to the macOS Keychain for credentials and to iCloud for discovery metadata (the non-secret "these accounts exist" index). Credentials never leave macOS.
- iOS discovers accounts purely by watching the iCloud `accounts/` directory tree. It does not hold tokens and does not attempt sign-in. This preserves today's iOS constraint ("no OAuth on iOS"). Active account selection on iOS is a client-side UI setting.
- Alternative considered: CloudKit private database. Rejected because iCloud Drive JSON already drives everything else and per-file diffable layout works well with `NSMetadataQuery`.

### Keychain layout per account
- Keep service `com.tenondev.tempo.claude.oauth` and key each account by setting `kSecAttrAccount` to the canonical accountId (lowercased email or synthetic id).
- Add a single "registry" Keychain item under the same service with `kSecAttrAccount = "__registry__"` that stores the encoded account list (accountId, email, displayName, createdAt). This keeps credentials and registry atomic in the same secure store and avoids putting the registry in iCloud.
- Because there are no active users, the legacy `credentials` slot is not migrated; it is simply deleted on first launch if it exists (silent cleanup, single sweep, no retry on failure).
- Alternative considered: one Keychain item per account plus a separate plist for the registry. Rejected because the registry and credentials can go out of sync across crashes or restores.

### iCloud layout
- New tree under `Tempo/accounts/<accountId>/`:
  - `usage.json` - current `UsageState` for that account.
  - `usage-history.json` - per-account history.
  - `latest.json` - latest relayed session from the local DB (session pipeline).
  - `account.json` - small non-secret metadata file with `{accountId, email, displayName, createdAt}`.
- `Tempo/accounts/index.json` - an ordered list of accountIds used as a fast index for iOS readers and widget configuration intents. Derived state; rebuildable from the `accounts/` directory.
- `Tempo/alert-preferences.json` and `Tempo/appearance-mode.json` stay at `Tempo/` because they are intentionally global.
- Legacy `Tempo/usage.json`, `Tempo/usage-history.json`, and `Tempo/latest.json` are neither read nor written by any target. They may linger in dev iCloud containers; developers delete them manually when convenient.

### No migration, no fallback
- On first macOS launch there is no file-copy, no legacy Keychain promotion, and no "default" account synthesized from flat files. If the registry is empty, the app shows the welcome flow and the user signs in.
- On iOS, if `Tempo/accounts/` is missing or empty, the app shows the "Connect via Mac app" state. It does not read the old flat files.
- The legacy Keychain `credentials` slot is deleted if present, as part of a one-shot startup cleanup. Stale iCloud files are left alone.
- This is explicit: the app is in development, data loss from prior builds is accepted, and the code is simpler as a result.

### Active account selection semantics
- macOS and iOS each maintain a local `activeAccountId` (`UserDefaults` on each platform; not iCloud). A user can view one account on the Mac while a different one is active on the iPhone.
- The iPhone's `activeAccountId` is the single source of truth for the watch. Every time it changes, iOS:
  1. Loads the active account's `UsageState` and most recent session from iCloud.
  2. Sends `updateApplicationContext` with the new `accountId`, label, and latest state so the watch always has the most current snapshot.
  3. Uses `transferUserInfo` only for durable session events (completion), tagged with `accountId`.
- The watch stores the last seen `accountId` in-memory only (not persisted). On launch it shows a waiting state until the iPhone relays.
- Alternative considered: persist active account on watch. Rejected because the user explicitly requested the watch follow the iPhone.

### UI navigation on macOS
- The menu bar popover gains an "Account" row at the top with the active account's email and a chevron that opens a native menu listing all known accounts plus "Add account" and "Manage accounts" actions. Switching active account updates local `activeAccountId`, triggers a widget reload, and retargets the detail window if open.
- The Welcome window's "Sign In" button always creates a new account. Sign-out in Preferences targets a specific account (picker in the sign-out UI).
- The Detail window binds to the active account and reloads when `activeAccountId` changes. Its header includes the account label.

### UI navigation on iOS
- Dashboard header gets a tappable account chip showing the active email; tap opens a sheet that lists all accounts, shows last-updated per account, and exposes a "Set as active" action. "Refresh via Mac" remains the entry point; adding an account is macOS-only.
- Activity/detail views filter by active account. Switching account happens through the header chip.

### Watch UX
- Dashboard header displays a short account label (email prefix, with an initials fallback). Tapping the label shows the full email in a sheet. There is no picker on the watch.
- `CompletionView` picks up the `accountId` label so users can tell which account's session completed.
- If the iPhone has no active account, the watch shows a "No accounts available" state with instructions to check the Mac app.

### Widget strategy
- `WidgetUsageSnapshot` schema is replaced with a new version that includes `accountId: String` and `accountLabel: String` as first-class fields. No tolerance for an older schema is required because no production widgets exist.
- Default widget (no intent) renders the active account's snapshot. For iOS and macOS, new AppIntents `SelectAccountIntent` let a user pin a specific widget to a given accountId. When the pinned account is removed, the widget falls back to the active account and shows a small "account removed" note.
- watchOS widget continues to render the active account only, matching the watch dashboard policy.

### Per-account polling cadence
- `UsagePoller` becomes an orchestrator that owns one `AccountPollingWorker` per account. Each worker has its own 15-minute scheduler and rate-limit backoff state; they run concurrently. Token refresh is still per-account because tokens are per-account. This preserves the existing 15-minute polling and backoff-to-3600s behavior in the per-account scope.
- Worker failures on one account do not cancel the others.

### Session ingestion per account
- `ClaudeLocalDBReader` matches sessions to an account by reading `~/.claude.json`'s `oauthAccount.emailAddress` at the time the session fired. If the CLI profile matches a known accountId, the session is tagged with that accountId. If not, the session is tagged with a special `unassigned` bucket and surfaced under a "CLI-only sessions" section in the detail window with a one-click "Associate with account" action.
- `SessionEventWriter` writes to `Tempo/accounts/<id>/latest.json`. Unassigned sessions go to `Tempo/accounts/unassigned/latest.json` so the iOS reader can still see them.

## Risks / Trade-offs

- [Risk] Stale iCloud files from prior dev builds may confuse testers. → Mitigation: developer-facing note in the README's testing section; no runtime handling.
- [Risk] Keychain cleanup that drops the legacy slot removes existing credentials from dev machines. → Mitigation: acceptable because the app has no production users; next launch prompts sign-in for each account the developer wants to restore.
- [Risk] accountId churn on Anthropic-side email change (rare). → Mitigation: treat accountId as stable once recorded; if the profile email changes, re-sign-in creates a new account and the old one can be removed from the registry.
- [Risk] Widget intent references an accountId that no longer exists. → Mitigation: widget falls back to active account and shows an "account removed" note; intent surfaces a "pick another account" link.
- [Risk] Unassigned CLI sessions confuse the user. → Mitigation: explicit "CLI-only sessions" bucket with a clear association flow.
- [Trade-off] Keeping the registry in Keychain adds one extra `SecItemCopyMatching` on startup. Negligible, and in exchange we get an atomic credential+metadata store.

## Open Questions

- When a user removes an account, do we keep their iCloud history file under `Tempo/accounts/retired/<accountId>/` or delete immediately? Current plan: delete immediately to keep the tree clean; finalize during tasks.
- Should the widget's `SelectAccountIntent` be configurable on all widget variants or only summary/ring? Current plan: all variants support it, and the compact variant truncates the label.
