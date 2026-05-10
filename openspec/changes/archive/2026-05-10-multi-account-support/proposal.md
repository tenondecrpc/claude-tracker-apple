## Why

Tempo is still in development with no active users, so we can adopt a multi-account model as the only supported shape. Users with more than one Anthropic account (personal + work, parallel subscriptions, team + client) need to track each account's usage and sessions in one place without signing in and out. A first-class multi-account model lets users sign in multiple accounts on macOS, navigate between them on the dashboards, and keep the watch glance honest by following whichever account is active on the iPhone. Because there are no production users, we SHALL NOT ship any migration, fallback, or backwards-compatible path for the previous single-account layout.

## What Changes

- iCloud usage, usage-history, and session payloads are partitioned per account from day one. The macOS writer produces `accounts/<accountId>/usage.json`, `accounts/<accountId>/usage-history.json`, and `accounts/<accountId>/latest.json`, plus an `accounts/index.json` enumerating known accounts. The legacy flat paths (`Tempo/usage.json`, etc.) SHALL NOT be written or read by any target.
- Account identifier is the email address from the Anthropic OAuth profile, normalized to lowercase and used as a stable accountId for iCloud paths, widget snapshots, and WatchConnectivity payloads. A fallback opaque id is used when the provider omits email (rare; legacy CLI-only sessions).
- The macOS app gains an `AccountRegistry` that can add, list, rename (display name only), and remove Anthropic accounts. Sign-in adds a new account; sign-out removes one by id; there is always at most one `activeAccountId`.
- Credential storage in the macOS Keychain keys by accountId rather than a single slot, so multiple OAuth refresh/access token sets can coexist.
- `UsagePoller` becomes multi-account: it maintains per-account schedule, rate-limit backoff, and last `UsageState`, and writes each account's snapshot to its own iCloud path.
- Local Claude Code session ingestion (`ClaudeLocalDBReader`, `SessionEventWriter`) tags each discovered session with an accountId derived from `~/.claude.json` / CLI profile context, and writes per-account `latest.json` instead of one global file.
- The iOS companion reads the iCloud `accounts/` tree, builds an in-memory directory of accounts, exposes an account picker in the dashboard and detail screens, and persists `activeAccountId` locally (not in iCloud).
- iOS relays only the active account's `UsageState` and latest session to the watch, with a new `accountId` field in the WatchConnectivity payload. Switching active account on iPhone triggers a fresh relay and widget reload.
- watchOS does not pick an account; it renders whatever accountId the iPhone is currently relaying, shows the account label (email or display name) in the dashboard header, and clears state when the iPhone has no active account.
- Widgets (macOS, iOS, watchOS) render the active account's snapshot. macOS and iOS widgets additionally support an optional account configuration intent so a user can pin a widget to a specific account even when the active selection changes.
- Alert preferences and appearance mode remain global (one setting for the app, not per account). Notifications include the account label so a sign-in banner or session alert identifies which account fired.
- Any stale or orphaned files under the legacy `Tempo/*.json` paths may exist on existing iCloud containers from prior development builds. Tempo SHALL ignore them. Developers can delete them manually when convenient.

## Capabilities

### New Capabilities

- `multi-account-registry`: Canonical model and storage for known Anthropic accounts on macOS. Owns accountId derivation from email, account list persistence, active account selection, and change notifications.
- `multi-account-icloud-layout`: iCloud directory contract (`Tempo/accounts/<accountId>/...`, `Tempo/accounts/index.json`) and read/write helpers shared by macOS and iOS. No migration or legacy support.
- `multi-account-navigation`: iOS + macOS UI for listing accounts, showing the active account, switching between accounts, and surfacing per-account usage, history, and session detail views.

### Modified Capabilities

- `macos-keychain-credentials`: Keychain entries are keyed by accountId instead of a single `credentials` account. The legacy fixed-slot contract is removed outright.
- `macos-oauth`: Sign-in flow adds an account rather than replacing one; sign-out removes a specific account; the welcome window exposes add-account and switch-account actions.
- `usage-polling` and `macos-usage-writer`: Polling loop runs per account, writes per-account iCloud files, and maintains per-account rate-limit backoff.
- `icloud-usage-sync`: iOS reader watches the per-account directory tree and materializes per-account state. The legacy single-file contract is removed.
- `icloud-history-sync`: Usage history is mirrored per account. Merge-and-dedupe runs within each account's history file.
- `watch-relay`: Relay payloads carry `accountId` and the relay is gated by iPhone's active account.
- `watch-dashboard` and `watch-session-receiver`: Watch renders the active account's label and clears state when no active account is relayed.
- `usage-widgets`: Widget snapshots carry `accountId` and optional per-widget account configuration; default widgets follow the active account.
- `session-info`: `SessionInfo` carries an `accountId` tag so per-account surfaces can filter correctly.

## Impact

- **Code**: macOS `CredentialStore`, `MacOSAPIClient`, `UsagePoller`, `UsageHistory`, `ClaudeLocalDBReader`, `SessionEventWriter`, `TempoMacApp`, welcome/preferences/detail windows. iOS `iCloudUsageReader`, `WatchRelayManager`, dashboard/activity views. watchOS dashboard + completion views. Widget snapshot model in `Shared/` plus all widget extensions.
- **Shared/**: New `Account` model (accountId, email, displayName, createdAt), updates to `UsageState` / `WidgetUsageSnapshot` / `SessionInfo` to carry `accountId`. iCloud path helpers in `TempoICloud`.
- **iCloud contract**: `Tempo/accounts/<accountId>/...` tree plus `accounts/index.json`. This is a high-risk change because it touches the cross-device sync surface, but because there are no production users we do not guard it with migration; developers clean up stale iCloud state manually if needed.
- **Keychain**: Accounts stored under service `com.tenondev.tempo.claude.oauth` with `kSecAttrAccount` set to the canonical accountId. A reserved `__registry__` slot holds the non-secret account list.
- **Widgets**: `WidgetUsageSnapshot` schema gains `accountId` and an optional label. Widget intents gain an `AccountIntent` for macOS and iOS.
- **WatchConnectivity**: `UsageState` and `SessionInfo` payloads gain `accountId` and an optional display label. No backwards compatibility is required on the watch.
- **Docs**: `docs/CONVENTIONS.md` and `docs/PLAN.md` updated to describe the multi-account model.
- **Test/verification**: `tools/widget_smoke_test.swift` extended to cover per-account snapshots. Manual verification required for keychain and iCloud per-account writes and watch relay switching.
