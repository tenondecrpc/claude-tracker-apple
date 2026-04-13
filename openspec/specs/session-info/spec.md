## Requirements

### Requirement: SessionInfo costUSD is always zero on subscription
The `costUSD` field SHALL be retained in `SessionInfo` but SHALL always be `0.0` for Claude Max subscription users. Claude Code does not expose per-session cost data via hooks or the local DB on subscription plans.

#### Scenario: Cost field present but zero
- **WHEN** a `SessionInfo` is created from Stop hook data
- **THEN** `costUSD` SHALL equal `0.0`

#### Scenario: Mock fixtures use zero cost
- **WHEN** `MockData.swift` provides sample `SessionInfo` values
- **THEN** `costUSD` SHALL be `0.0` in all fixtures

### Requirement: LocalProjectStat model
`LocalProjectStat` SHALL include the following fields in addition to existing `dirName`, `displayName`, and `sessionCount`:
- `messages7d: Int` - user message count in the last 7 days
- `toolCalls7d: Int` - tool_use block count in the last 7 days
- `totalTokens7d: Int` - sum of input + output tokens in the last 7 days
- `costEquiv7d: Double` - API-equivalent cost in USD in the last 7 days

#### Scenario: Model initialized with 7-day fields
- **WHEN** `LocalProjectStat` is constructed from JSONL parsing results
- **THEN** all four 7-day fields SHALL be populated with computed values (defaulting to 0 when no data is available)

#### Scenario: Existing sessionCount unchanged
- **WHEN** `LocalProjectStat` is constructed
- **THEN** `sessionCount` SHALL continue to reflect the total count of `.jsonl` files in the project directory (all-time, not filtered)
