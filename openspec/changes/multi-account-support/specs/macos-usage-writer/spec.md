## MODIFIED Requirements

### Requirement: Usage polled every 15 minutes on macOS per account
The macOS app SHALL poll `GET https://api.anthropic.com/api/oauth/usage` at a 15-minute interval per account while that account has valid credentials. The request SHALL include `Authorization: Bearer <access_token>` for that account and `anthropic-beta: oauth-2025-04-20` headers. A per-account poll SHALL fire immediately when that account's credentials become valid.

The poller SHALL expose the latest `UsageState` per account as an observable collection (`latestUsageByAccount: [String: UsageState]`) so that SwiftUI views can reactively display current usage data for the currently active account without additional iCloud reads. A convenience `latestUsage(for: accountId)` accessor SHALL return that account's snapshot (or `nil`).

#### Scenario: Poll fires on schedule per account
- **WHEN** 15 minutes elapse since the last successful poll for account A
- **THEN** the app issues a new `GET /api/oauth/usage` request for account A

#### Scenario: Poll fires immediately after sign-in
- **WHEN** OAuth authentication succeeds for a new accountId
- **THEN** a poll is issued immediately for that accountId without waiting for the 15-minute interval

#### Scenario: Latest usage state is observable per account
- **WHEN** a poll returns HTTP 200 with valid usage data for account A
- **THEN** `latestUsage(for: accountA)` returns the updated state and any observing SwiftUI views bound to that accountId re-render

### Requirement: Usage response mapped to UsageState and written only to per-account iCloud paths
The poller SHALL map the API response to `UsageState` and write it to the per-account iCloud path `Tempo/accounts/<accountId>/usage.json`. Tempo SHALL NOT write `Tempo/usage.json` or any other legacy flat path. All file operations SHALL go through the `TempoICloud` path helpers.

#### Scenario: UsageState written to per-account iCloud path
- **WHEN** a poll for account A returns HTTP 200 with valid usage data
- **THEN** the mapped `UsageState` (tagged with account A's id) is encoded as JSON and written to `Tempo/accounts/<A>/usage.json`

#### Scenario: Legacy flat path is never written
- **WHEN** the macOS writer produces any `UsageState`
- **THEN** no write is performed against `Tempo/usage.json` and no legacy path is touched

#### Scenario: iCloud account directory created if missing
- **WHEN** the `Tempo/accounts/<accountId>/` directory does not exist for a given account
- **THEN** the directory is created before writing `usage.json`

#### Scenario: Utilization normalized
- **WHEN** API returns `"five_hour": { "utilization": 79.0 }` for account A
- **THEN** `UsageState.utilization5h` is `0.79` in the written JSON under `accounts/<A>/usage.json`

### Requirement: Reset timestamp reconciliation preserves last known value per account
If the API response omits `resets_at` (null or missing) for an account, the poller SHALL retain that account's previously known reset timestamp in the written `UsageState`. A reset is detected when that account's utilization drops after having been above 0; in that case the old timestamp is discarded.

#### Scenario: Null resets_at preserves prior value per account
- **WHEN** the API returns `"resets_at": null` for account A and a previous `resetAt5h` exists for account A
- **THEN** the written `UsageState.resetAt5h` in `accounts/<A>/usage.json` retains the previous value

### Requirement: Exponential backoff on 429 is per account
On HTTP 429, the per-account poller SHALL back off exponentially. If a `Retry-After` header is present, that value (seconds) is used as the delay for that account, bounded to at least 60 seconds. If no `Retry-After` header is present, the delay doubles from that account's current interval. The delay SHALL be capped at 3600 seconds. Normal 15-minute polling resumes for that account after one successful response. Other accounts SHALL continue on their own schedules.

#### Scenario: 429 with Retry-After header for one account
- **WHEN** the API returns 429 with `Retry-After: 120` for account A
- **THEN** account A's next poll is delayed at least 120 seconds and account B is not affected

#### Scenario: Recovery after 429
- **WHEN** a poll for account A after backoff returns 200
- **THEN** account A's polling interval resets to 15 minutes

### Requirement: Tempo OAuth credentials updated per account after token refresh
When the poller triggers a Tempo OAuth token refresh due to a 401 or expiry for an account, that account's new Tempo OAuth credentials SHALL be written back to the macOS Keychain under its accountId slot before retrying the API call. Claude Code CLI credentials SHALL NOT be refreshed or written by Tempo.

#### Scenario: Keychain credentials updated after Tempo OAuth refresh
- **WHEN** a token refresh succeeds during polling for account A
- **THEN** account A's Tempo OAuth Keychain item (service `com.tenondev.tempo.claude.oauth`, account `<A>`) is updated with the new `access_token` and `expiresAt`

#### Scenario: CLI credentials are not refreshed
- **WHEN** a request using Claude Code CLI credentials returns 401
- **THEN** Tempo does not use Claude Code's refresh token and does not write to the Claude Code Keychain item

### Requirement: macOS writes per-account widget snapshot after successful polls
After a successful macOS usage poll for an account, the app SHALL derive a widget snapshot tagged with that accountId and write it to shared App Group storage for the macOS widget extension. The active-account widget surface SHALL use the snapshot for the currently active accountId. Per-account widgets configured with an `AccountIntent` SHALL use the snapshot for their configured accountId.

#### Scenario: Widget snapshot written after poll success
- **WHEN** the macOS poller receives a valid usage response for account A and updates `latestUsageByAccount[A]`
- **THEN** the app writes a widget snapshot (with `accountId = A`) to the macOS widget App Group storage

#### Scenario: Snapshot timestamp matches successful poll
- **WHEN** the app writes a per-account widget snapshot
- **THEN** the snapshot records the successful poll time as its freshness timestamp

#### Scenario: Active-account snapshot is also surfaced
- **WHEN** the active account is A and a new snapshot for A is written
- **THEN** the "active account" widget surface reads the new snapshot on its next timeline reload

### Requirement: macOS reloads widget timelines only after valid snapshot writes
The macOS app SHALL request widget timeline reloads only after it has successfully written a valid widget snapshot for a specific account. Failed polls SHALL NOT clear the previous valid widget snapshot for that account.

#### Scenario: Widget timelines reloaded after valid write
- **WHEN** the app successfully writes a new widget snapshot for account A
- **THEN** it calls WidgetKit reload APIs for Tempo's macOS widget kinds

#### Scenario: Failed poll preserves last valid widget content for that account
- **WHEN** a macOS usage poll for account A fails because of auth, rate limit, or network error
- **THEN** account A's previous valid widget snapshot remains in shared storage and is not deleted or overwritten
