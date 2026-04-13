## REMOVED Requirements

### Requirement: SessionInfo carries limit reset timestamp
**Reason**: The Stop hook stdin payload does not include limit reset timestamps. This data is account-level, only available from the OAuth API, and belongs in `UsageState.resetAt5h` - not in a per-session model.
**Migration**: Use `UsageState.resetAt5h` / `resetAt7d` for limit reset timestamps.

#### Scenario: Limit reset data not in session model
- **WHEN** a Stop hook fires and a `SessionInfo` is created
- **THEN** the model SHALL NOT contain any limit reset timestamp field

### Requirement: SessionInfo carries double-limit active flag
**Reason**: No Stop hook env var or transcript field exposes whether the double-limit promotion is active. The field cannot be populated.
**Migration**: No replacement - this flag has no valid data source in the current architecture.

#### Scenario: Double-limit flag not in session model
- **WHEN** a Stop hook fires and a `SessionInfo` is created
- **THEN** the model SHALL NOT contain an `isDoubleLimitActive` field

## ADDED Requirements

### Requirement: SessionInfo costUSD is always zero on subscription
The `costUSD` field SHALL be retained in `SessionInfo` but SHALL always be `0.0` for Claude Max subscription users. Claude Code does not expose per-session cost data via hooks or the local DB on subscription plans.

#### Scenario: Cost field present but zero
- **WHEN** a `SessionInfo` is created from Stop hook data
- **THEN** `costUSD` SHALL equal `0.0`

#### Scenario: Mock fixtures use zero cost
- **WHEN** `MockData.swift` provides sample `SessionInfo` values
- **THEN** `costUSD` SHALL be `0.0` in all fixtures
