## Purpose

Define how the macOS app polls usage and publishes durable usage snapshots for iCloud consumers and desktop widgets.

## Requirements

### Requirement: Usage polled every 30 minutes on macOS
The macOS app SHALL poll `GET https://api.anthropic.com/api/oauth/usage` at a **30-minute** interval while the user is authenticated. The request SHALL include `Authorization: Bearer <access_token>` and `anthropic-beta: oauth-2025-04-20` headers. A poll SHALL fire immediately on successful authentication.

> **Rate-limit finding (2026-03-28):** A 15-minute default interval reliably triggers HTTP 429 from Anthropic on this endpoint during normal use. The minimum safe interval observed in production is **30 minutes**. The interval MUST NOT be lowered below 30 minutes in any configuration. Manual one-off refreshes (user-initiated) are acceptable and are not affected by this constraint.

The poller SHALL expose the latest `UsageState` as an observable property (`latestUsage: UsageState?`) so that SwiftUI views can reactively display current usage data without additional iCloud reads.

#### Scenario: Poll fires on schedule
- **WHEN** 30 minutes elapse since the last successful poll
- **THEN** the app issues a new `GET /api/oauth/usage` request

#### Scenario: Poll fires immediately after sign-in
- **WHEN** OAuth authentication succeeds
- **THEN** a poll is issued immediately without waiting for the 30-minute interval

#### Scenario: Latest usage state is observable by views
- **WHEN** a poll returns HTTP 200 with valid usage data
- **THEN** the `latestUsage: UsageState?` property is updated and any observing SwiftUI views re-render

### Requirement: Usage response mapped to UsageState and written to iCloud
The poller SHALL map the API response to `UsageState` (same mapping as `usage-polling` spec: divide utilization by 100, parse ISO 8601 dates). The resulting `UsageState` SHALL be encoded as JSON and written to `~/Library/Mobile Documents/com~apple~CloudDocs/Tempo/usage.json`.

#### Scenario: UsageState written to iCloud
- **WHEN** a poll returns HTTP 200 with valid usage data
- **THEN** the mapped `UsageState` is encoded as JSON and written to `Tempo/usage.json` in iCloud Drive

#### Scenario: iCloud directory created if missing
- **WHEN** the `Tempo/` directory does not exist in iCloud Drive
- **THEN** the directory is created before writing `usage.json`

#### Scenario: Utilization normalized
- **WHEN** API returns `"five_hour": { "utilization": 79.0 }`
- **THEN** `UsageState.utilization5h` is `0.79` in the written JSON

### Requirement: Reset timestamp reconciliation preserves last known value
If the API response omits `resets_at` (null or missing), the poller SHALL retain the previously known reset timestamp in the written `UsageState`. A reset is detected when utilization drops after having been above 0 - in that case the old timestamp is discarded.

#### Scenario: Null resets_at preserves prior value
- **WHEN** the API returns `"resets_at": null` and a previous `resetAt5h` exists
- **THEN** the written `UsageState.resetAt5h` retains the previous value

### Requirement: Exponential backoff on 429
On HTTP 429, the poller SHALL back off exponentially. If a `Retry-After` header is present, that value (seconds) is used as the minimum delay. The delay SHALL be capped at 3600 seconds. Normal 30-minute polling resumes after one successful response.

#### Scenario: 429 with Retry-After header
- **WHEN** the API returns 429 with `Retry-After: 120`
- **THEN** the next poll is delayed at least 120 seconds

#### Scenario: Recovery after 429
- **WHEN** a poll after backoff returns 200
- **THEN** the polling interval resets to 30 minutes

### Requirement: Credentials file updated after token refresh
When the poller triggers a token refresh (due to 401 or expiry), the new credentials SHALL be written back to `~/.config/tempo-for-claude/credentials.json` before retrying the API call.

#### Scenario: Credentials file updated after refresh
- **WHEN** a token refresh succeeds during polling
- **THEN** `credentials.json` is updated with the new `access_token` and `expiresAt`

### Requirement: macOS writes widget snapshot after successful usage polls
After a successful macOS usage poll, the app SHALL derive a widget snapshot from the latest `UsageState` and write it to shared App Group storage for the macOS widget extension.

#### Scenario: Widget snapshot written after poll success
- **WHEN** the macOS poller receives a valid usage response and updates `latestUsage`
- **THEN** the app writes a corresponding widget snapshot to the macOS widget App Group storage

#### Scenario: Snapshot timestamp matches successful poll
- **WHEN** the app writes a widget snapshot after a successful poll
- **THEN** the snapshot records the successful poll time as its freshness timestamp

### Requirement: macOS reloads widget timelines only after valid snapshot writes
The macOS app SHALL request widget timeline reloads only after it has successfully written a valid widget snapshot. Failed polls SHALL NOT clear the previous valid widget snapshot.

#### Scenario: Widget timelines reloaded after valid write
- **WHEN** the app successfully writes a new widget snapshot
- **THEN** it calls WidgetKit reload APIs for Tempo's macOS widget kinds

#### Scenario: Failed poll preserves last valid widget content
- **WHEN** a macOS usage poll fails because of auth, rate limit, or network error
- **THEN** the previous valid widget snapshot remains in shared storage and is not deleted or overwritten
