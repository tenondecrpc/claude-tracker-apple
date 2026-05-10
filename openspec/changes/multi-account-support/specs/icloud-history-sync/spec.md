## MODIFIED Requirements

### Requirement: Usage history is mirrored to iCloud per account when sync is enabled
When Sync History via iCloud is enabled, the macOS app SHALL mirror usage-history snapshots per account to `Tempo/accounts/<accountId>/usage-history.json`. Each account's history SHALL be an isolated file; history from different accounts SHALL NOT be merged into a single file.

#### Scenario: Local append writes to iCloud mirror for the correct account
- **WHEN** a new `UsageSnapshot` is appended for account A while iCloud sync is enabled
- **THEN** the app writes updated history to `Tempo/accounts/<A>/usage-history.json`

#### Scenario: iCloud sync disabled prevents mirror writes
- **WHEN** Sync History via iCloud is disabled
- **THEN** local history continues to persist locally per account and no iCloud mirror write is attempted

### Requirement: Local and iCloud history converge per account by merge-and-dedupe
For each account, the system SHALL merge local and iCloud snapshot sets for that account, dedupe equivalent snapshots, sort by timestamp, and prune to retention policy before persistence. Merge SHALL be scoped to the account's own history; snapshots SHALL NOT be cross-attributed to a different account.

#### Scenario: Multi-Mac overlap for one account
- **WHEN** local and iCloud history for account A contain overlapping snapshots from different Macs
- **THEN** duplicate-equivalent snapshots are stored once in account A's merged result

#### Scenario: One side has additional snapshots
- **WHEN** either local or iCloud history has snapshots absent on the other side for account A
- **THEN** the merged result for account A includes the union of snapshots after pruning

#### Scenario: No cross-account leakage
- **WHEN** merging history for account A
- **THEN** snapshots tagged with account B remain in account B's file and do not appear in account A's merged result

### Requirement: iCloud sync failures do not block local history behavior
Failures reading/writing iCloud history SHALL NOT interrupt local history collection, chart rendering, or polling for any account.

#### Scenario: iCloud unavailable for one account's write
- **WHEN** iCloud container or an account's history file is temporarily unavailable
- **THEN** that account's local history append and save continue, and sync retries on future sync cycles; other accounts continue to mirror normally

#### Scenario: iCloud returns after outage
- **WHEN** iCloud access becomes available again
- **THEN** the app resumes per-account merge-and-mirror behavior without requiring app reinstall or data reset
