## ADDED Requirements

### Requirement: iCloud account-partitioned directory layout
Tempo SHALL store per-account usage, history, and session state under a directory tree `Tempo/accounts/<accountId>/` inside the Tempo iCloud container. Shared, global state (alert preferences, appearance mode) SHALL remain at the root of `Tempo/`.

The per-account directory SHALL contain:
- `account.json` - non-secret metadata written by the macOS registry
- `usage.json` - latest `UsageState` for the account
- `usage-history.json` - per-account history snapshots
- `latest.json` - latest session info ingested from the local Claude Code database

A sibling file `Tempo/accounts/index.json` SHALL list known accountIds in user-visible order.

#### Scenario: Directory path for OAuth account
- **WHEN** an account has `accountId = "user@example.com"`
- **THEN** that account's files live under `Tempo/accounts/user@example.com/`

#### Scenario: index.json enumerates accountIds
- **WHEN** two accounts are active in the registry
- **THEN** `Tempo/accounts/index.json` serializes both accountIds in the same order the registry exposes them

#### Scenario: Global files remain at root
- **WHEN** alert preferences or appearance mode are synced
- **THEN** they are written to `Tempo/alert-preferences.json` and `Tempo/appearance-mode.json` and are NOT duplicated under `accounts/<id>/`

### Requirement: Shared iCloud path helpers
`Shared/TempoICloud.swift` SHALL expose helpers for building per-account iCloud URLs and resolving the `accounts/` tree for both macOS writers and iOS readers. Callers SHALL use these helpers instead of building paths ad hoc.

The module SHALL provide at least:
- `accountsDirectoryURL()` - returns the base `Tempo/accounts/` URL when the ubiquity container is available
- `accountDirectoryURL(for accountId: String)` - returns the per-account directory URL with filesystem-safe percent-encoding applied
- `indexFileURL()` - returns the URL of `Tempo/accounts/index.json`
- `usageFileURL(for accountId: String)` / `usageHistoryFileURL(for accountId: String)` / `latestSessionFileURL(for accountId: String)` / `accountMetadataFileURL(for accountId: String)`

#### Scenario: Helper returns canonical URL
- **WHEN** a caller asks for the usage URL of `"user@example.com"`
- **THEN** the helper returns `.../Tempo/accounts/user@example.com/usage.json` based on the resolved ubiquity container

#### Scenario: Helper escapes unsafe characters in path only
- **WHEN** `accountId` contains a character outside `[a-z0-9._@-]`
- **THEN** the returned URL uses percent-encoding for that character in the directory segment while the accountId value passed back to callers is unchanged

### Requirement: No migration and no legacy fallback
Tempo SHALL treat the per-account tree as the sole layout. The app SHALL NOT read, write, copy, or promote the legacy flat files `Tempo/usage.json`, `Tempo/usage-history.json`, or `Tempo/latest.json`. If `Tempo/accounts/` is absent, Tempo SHALL present an empty state rather than fall back to legacy paths.

#### Scenario: Legacy flat files are ignored
- **WHEN** `Tempo/usage.json` exists in iCloud but `Tempo/accounts/` does not
- **THEN** no target reads that file and the iOS reader shows the "Connect via Mac app" state

#### Scenario: No legacy writes
- **WHEN** the macOS writer produces a new `UsageState`
- **THEN** it is written only to `Tempo/accounts/<accountId>/usage.json` and never to `Tempo/usage.json`

#### Scenario: Empty accounts tree is empty state
- **WHEN** `Tempo/accounts/` exists but is empty or missing `index.json`
- **THEN** iOS shows the empty "no accounts" state rather than substituting legacy data

### Requirement: Account removal deletes the account directory
When an account is removed from the registry, its `Tempo/accounts/<accountId>/` directory SHALL be deleted. Tempo SHALL NOT preserve a retired copy.

#### Scenario: Remove deletes the directory
- **WHEN** an account is removed while its iCloud directory contains `usage.json`, `usage-history.json`, and `latest.json`
- **THEN** those files and the enclosing directory are deleted from iCloud
