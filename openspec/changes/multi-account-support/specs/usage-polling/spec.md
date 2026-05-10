## MODIFIED Requirements

### Requirement: Usage polled every 15 minutes per account
The macOS app SHALL poll `GET https://api.anthropic.com/api/oauth/usage` at a 15-minute interval for each registered account that has valid credentials. Each account SHALL have its own independent poll schedule, rate-limit backoff state, and in-memory `latestUsage` snapshot. The request SHALL include `Authorization: Bearer <access_token>` for that account and `anthropic-beta: oauth-2025-04-20` headers. A per-account poll SHALL fire immediately when that account's credentials become valid (either new sign-in, successful migration, or refresh recovery).

#### Scenario: Poll fires on schedule per account
- **WHEN** 15 minutes elapse since the last successful poll for account A
- **THEN** the macOS poller issues a new `GET /api/oauth/usage` request for account A, independent of other accounts' schedules

#### Scenario: Poll fires immediately after authentication
- **WHEN** sign-in succeeds for a new accountId
- **THEN** a poll is issued immediately for that accountId (not waiting for the 15-minute interval)

#### Scenario: Account-level failure does not halt others
- **WHEN** account A enters exponential backoff because of a 429 response
- **THEN** account B continues polling on its normal 15-minute schedule

### Requirement: Response mapped to per-account UsageState with normalized utilization
For each poll, the poller SHALL map the API response to `UsageState` and tag the result with the associated `accountId`. `five_hour.utilization` (0-100) SHALL be divided by 100 to produce `utilization5h` (0.0-1.0). `seven_day.utilization` (0-100) SHALL be divided by 100 to produce `utilization7d`. `five_hour.resets_at` and `seven_day.resets_at` (ISO 8601 strings) SHALL be parsed to `Date`. `isMocked` SHALL be `false`. The resulting `UsageState` SHALL be written to the per-account iCloud path (see `icloud-usage-sync` and `macos-usage-writer` specs) instead of a single shared path.

#### Scenario: Utilization normalized
- **WHEN** API returns `"five_hour": { "utilization": 79.0 }` for account A
- **THEN** account A's `UsageState.utilization5h` is `0.79`

#### Scenario: Per-account accountId tagging
- **WHEN** the poller receives a response for account A
- **THEN** the written `UsageState` includes `accountId` equal to account A's canonical id

#### Scenario: Reset timestamp parsed
- **WHEN** API returns `"resets_at": "2026-03-27T18:30:00.000000+00:00"`
- **THEN** `UsageState.resetAt5h` is the corresponding `Date` for that account

### Requirement: Reset timestamp reconciliation preserves last known value per account
If the API response omits `resets_at` (null or missing), the per-account poller SHALL retain that account's previously known reset timestamp. A reset is detected when `utilization` drops after having been above 0 in that account's own poll history; in that case the old timestamp for that account is discarded.

#### Scenario: Null resets_at preserves prior value per account
- **WHEN** the API returns `"resets_at": null` for account A and a previous `resetAt5h` exists for account A
- **THEN** account A's `UsageState.resetAt5h` retains the previous value

#### Scenario: Utilization drop signals reset for that account only
- **WHEN** account A's `utilization5h` drops from above 0.0 to near 0.0 in consecutive polls while account B is unchanged
- **THEN** only account A's previous `resetAt5h` is discarded and replaced; account B is unaffected

### Requirement: API response decoding
The `UsagePoller.fetchUsage(for: accountId)` method SHALL decode the full API response including the optional `extra_usage` field. The internal `Response` struct SHALL include:
- `five_hour: Window`
- `seven_day: Window`
- `extra_usage: ExtraUsage?`

The decoded `ExtraUsage` SHALL be passed through to the returned `UsageState` for that account.

#### Scenario: API response with extra_usage present
- **WHEN** the API returns a response containing `"extra_usage": {"is_enabled": true, "monthly_limit": 2000, "used_credits": 530, "utilization": 26.5}` for account A
- **THEN** `fetchUsage(for: accountA)` returns a `UsageState` with `extraUsage` populated and `accountId` equal to account A's id

#### Scenario: API response without extra_usage
- **WHEN** the API returns a response without the `extra_usage` field
- **THEN** `fetchUsage(for:)` returns a `UsageState` with `extraUsage = nil`

### Requirement: Exponential backoff on 429 is per account
On HTTP 429, the account's poller SHALL back off exponentially. If a `Retry-After` header is present, that value (seconds) is used as the delay for that account, bounded to at least 60 seconds. If no `Retry-After` header is present, the delay doubles from that account's current interval. The delay SHALL be capped at 3600 seconds (1 hour). Normal 15-minute polling resumes for that account after one successful response. Other accounts SHALL NOT inherit the backoff.

#### Scenario: 429 with Retry-After header for one account
- **WHEN** the API returns 429 with `Retry-After: 120` for account A
- **THEN** account A's next poll is delayed at least 120 seconds while account B continues on its normal schedule

#### Scenario: Backoff cap per account
- **WHEN** repeated 429s would double account A's interval beyond 3600 seconds
- **THEN** account A's interval is capped at 3600 seconds and account B is unaffected

#### Scenario: Recovery after 429
- **WHEN** a poll for account A after backoff returns 200
- **THEN** account A's polling interval resets to 15 minutes
