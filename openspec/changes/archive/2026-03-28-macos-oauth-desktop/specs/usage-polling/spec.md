## MODIFIED Requirements

### Requirement: Usage polled every 15 minutes
The ~~iOS~~ **macOS** app SHALL poll `GET https://api.anthropic.com/api/oauth/usage` at a 15-minute interval while the ~~iOS app is in the foreground and~~ the user is authenticated. The request SHALL include `Authorization: Bearer <access_token>` and `anthropic-beta: oauth-2025-04-20` headers. The macOS app SHALL poll continuously (not gated by foreground state, since menu bar apps are always running).

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
