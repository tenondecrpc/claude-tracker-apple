## MODIFIED Requirements

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
