## MODIFIED Requirements

### Requirement: SessionInfo carries accountId
`SessionInfo` SHALL include an `accountId: String` field identifying the Anthropic account that owns the session. For sessions ingested from `~/.claude/` that do not match any registered account, `accountId` SHALL be the literal string `"unassigned"`. `SessionInfo` SHALL continue to be `Codable` and suitable for WatchConnectivity transport.

The watch receiver SHALL only surface a completion alert when the received `SessionInfo.accountId` matches the currently active accountId on the watch.

#### Scenario: SessionInfo created with matching accountId
- **WHEN** a session is ingested and its CLI profile email matches registered account A
- **THEN** the resulting `SessionInfo` has `accountId = A`

#### Scenario: SessionInfo created without a matching account
- **WHEN** a session is ingested and its CLI profile email does not match any registered account
- **THEN** the resulting `SessionInfo` has `accountId = "unassigned"`

#### Scenario: WatchConnectivity payload includes accountId
- **WHEN** a `SessionInfo` is relayed to the watch
- **THEN** the encoded dictionary includes the `accountId` field

#### Scenario: Mock fixtures carry accountId
- **WHEN** `MockData.swift` provides sample `SessionInfo` values
- **THEN** every fixture includes a non-empty `accountId`

### Requirement: SessionInfo costUSD is always zero on subscription
The `costUSD` field SHALL be retained in `SessionInfo` but SHALL always be `0.0` for Claude Max subscription users. Claude Code does not expose per-session cost data via hooks or the local DB on subscription plans.

#### Scenario: Cost field present but zero
- **WHEN** a `SessionInfo` is created from Stop hook data
- **THEN** `costUSD` SHALL equal `0.0`

#### Scenario: Mock fixtures use zero cost
- **WHEN** `MockData.swift` provides sample `SessionInfo` values
- **THEN** `costUSD` SHALL be `0.0` in all fixtures

### Requirement: LocalProjectStat carries accountId
`LocalProjectStat` SHALL include `accountId: String` in addition to its existing fields (`dirName`, `displayName`, `sessionCount`, `messages7d`, `toolCalls7d`, `totalTokens7d`, `costEquiv7d`). Project stats SHALL be scoped to a specific account so per-account detail views can filter cleanly.

#### Scenario: Model initialized with accountId
- **WHEN** `LocalProjectStat` is constructed from JSONL parsing results for a project owned by account A
- **THEN** `accountId` is set to `A` and all other existing fields are populated as before

#### Scenario: Unassigned project stats
- **WHEN** the project's session ownership cannot be matched to any registered account
- **THEN** `LocalProjectStat.accountId` is `"unassigned"`

#### Scenario: Existing sessionCount unchanged
- **WHEN** `LocalProjectStat` is constructed
- **THEN** `sessionCount` SHALL continue to reflect the total count of `.jsonl` files in the project directory (all-time, not filtered)
