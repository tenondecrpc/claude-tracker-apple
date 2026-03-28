## ADDED Requirements

### Requirement: Usage polled every 15 minutes on macOS
The macOS app SHALL poll `GET https://api.anthropic.com/api/oauth/usage` at a 15-minute interval while the user is authenticated. The request SHALL include `Authorization: Bearer <access_token>` and `anthropic-beta: oauth-2025-04-20` headers. A poll SHALL fire immediately on successful authentication.

#### Scenario: Poll fires on schedule
- **WHEN** 15 minutes elapse since the last successful poll
- **THEN** the app issues a new `GET /api/oauth/usage` request

#### Scenario: Poll fires immediately after sign-in
- **WHEN** OAuth authentication succeeds
- **THEN** a poll is issued immediately without waiting for the 15-minute interval

### Requirement: Usage response mapped to UsageState and written to iCloud
The poller SHALL map the API response to `UsageState` (same mapping as `usage-polling` spec: divide utilization by 100, parse ISO 8601 dates). The resulting `UsageState` SHALL be encoded as JSON and written to `~/Library/Mobile Documents/com~apple~CloudDocs/ClaudeTracker/usage.json`.

#### Scenario: UsageState written to iCloud
- **WHEN** a poll returns HTTP 200 with valid usage data
- **THEN** the mapped `UsageState` is encoded as JSON and written to `ClaudeTracker/usage.json` in iCloud Drive

#### Scenario: iCloud directory created if missing
- **WHEN** the `ClaudeTracker/` directory does not exist in iCloud Drive
- **THEN** the directory is created before writing `usage.json`

#### Scenario: Utilization normalized
- **WHEN** API returns `"five_hour": { "utilization": 79.0 }`
- **THEN** `UsageState.utilization5h` is `0.79` in the written JSON

### Requirement: Reset timestamp reconciliation preserves last known value
If the API response omits `resets_at` (null or missing), the poller SHALL retain the previously known reset timestamp in the written `UsageState`. A reset is detected when utilization drops after having been above 0 — in that case the old timestamp is discarded.

#### Scenario: Null resets_at preserves prior value
- **WHEN** the API returns `"resets_at": null` and a previous `resetAt5h` exists
- **THEN** the written `UsageState.resetAt5h` retains the previous value

### Requirement: Exponential backoff on 429
On HTTP 429, the poller SHALL back off exponentially. If a `Retry-After` header is present, that value (seconds) is used as the minimum delay. The delay SHALL be capped at 3600 seconds. Normal 15-minute polling resumes after one successful response.

#### Scenario: 429 with Retry-After header
- **WHEN** the API returns 429 with `Retry-After: 120`
- **THEN** the next poll is delayed at least 120 seconds

#### Scenario: Recovery after 429
- **WHEN** a poll after backoff returns 200
- **THEN** the polling interval resets to 15 minutes

### Requirement: credentials.json updated after token refresh
When the poller triggers a token refresh (due to 401 or expiry), the new credentials SHALL be written back to `~/.config/claude-tracker/credentials.json` before retrying the API call.

#### Scenario: Credentials file updated after refresh
- **WHEN** a token refresh succeeds during polling
- **THEN** `credentials.json` is updated with the new `access_token` and `expiresAt`
