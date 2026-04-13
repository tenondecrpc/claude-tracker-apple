### Requirement: Usage polled every 15 minutes
The **macOS** app SHALL poll `GET https://api.anthropic.com/api/oauth/usage` at a 15-minute interval while the user is authenticated. The request SHALL include `Authorization: Bearer <access_token>` and `anthropic-beta: oauth-2025-04-20` headers. The macOS app SHALL poll continuously (not gated by foreground state, since menu bar apps are always running). A poll SHALL fire immediately on successful authentication.

#### Scenario: Poll fires on schedule
- **WHEN** 15 minutes elapse since the last successful poll
- **THEN** the macOS poller issues a new `GET /api/oauth/usage` request

#### Scenario: Poll fires immediately after authentication
- **WHEN** the macOS app successfully authenticates (on launch or sign-in)
- **THEN** a poll is issued immediately (not waiting for the 15-minute interval)

### Requirement: Response mapped to UsageState with normalized utilization
The poller SHALL map the API response to `UsageState`. `five_hour.utilization` (0–100) SHALL be divided by 100 to produce `utilization5h` (0.0–1.0). `seven_day.utilization` (0–100) SHALL be divided by 100 to produce `utilization7d`. `five_hour.resets_at` and `seven_day.resets_at` (ISO 8601 strings) SHALL be parsed to `Date`. `isMocked` SHALL be `false`. The resulting `UsageState` SHALL be written to iCloud Drive (see `icloud-usage-sync` spec) instead of being consumed directly by iOS.

#### Scenario: Utilization normalized
- **WHEN** API returns `"five_hour": { "utilization": 79.0 }`
- **THEN** `UsageState.utilization5h` is `0.79`

#### Scenario: Reset timestamp parsed
- **WHEN** API returns `"resets_at": "2026-03-27T18:30:00.000000+00:00"`
- **THEN** `UsageState.resetAt5h` is the corresponding `Date`

### Requirement: Reset timestamp reconciliation preserves last known value
If the API response omits `resets_at` (null or missing), the poller SHALL retain the previously known reset timestamp. A reset is detected when `utilization` drops after having been above 0 - in that case the old timestamp is discarded.

#### Scenario: Null resets_at preserves prior value
- **WHEN** the API returns `"resets_at": null` and a previous `resetAt5h` exists
- **THEN** `UsageState.resetAt5h` retains the previous value

#### Scenario: Utilization drop signals reset
- **WHEN** `utilization5h` drops from above 0.0 to near 0.0 in consecutive polls
- **THEN** the previous `resetAt5h` is discarded and replaced with the new value (or nil)

### Requirement: API response decoding
The `UsagePoller.fetchUsage()` method SHALL decode the full API response including the optional `extra_usage` field. The internal `Response` struct SHALL include:
- `five_hour: Window`
- `seven_day: Window`
- `extra_usage: ExtraUsage?`

The decoded `ExtraUsage` SHALL be passed through to the returned `UsageState`.

#### Scenario: API response with extra_usage present
- **WHEN** the API returns a response containing `"extra_usage": {"is_enabled": true, "monthly_limit": 2000, "used_credits": 530, "utilization": 26.5}`
- **THEN** `fetchUsage()` returns a `UsageState` with `extraUsage` populated

#### Scenario: API response without extra_usage
- **WHEN** the API returns a response without the `extra_usage` field
- **THEN** `fetchUsage()` returns a `UsageState` with `extraUsage = nil`

### Requirement: Exponential backoff on 429
On HTTP 429, the poller SHALL back off exponentially. If a `Retry-After` header is present, that value (seconds) is used as the minimum delay. The delay SHALL be capped at 3600 seconds (1 hour). Normal 15-minute polling resumes after one successful response.

#### Scenario: 429 with Retry-After header
- **WHEN** the API returns 429 with `Retry-After: 120`
- **THEN** the next poll is delayed at least 120 seconds

#### Scenario: Backoff cap
- **WHEN** repeated 429s would double the interval beyond 3600 seconds
- **THEN** the interval is capped at 3600 seconds

#### Scenario: Recovery after 429
- **WHEN** a poll after backoff returns 200
- **THEN** the polling interval resets to 15 minutes
