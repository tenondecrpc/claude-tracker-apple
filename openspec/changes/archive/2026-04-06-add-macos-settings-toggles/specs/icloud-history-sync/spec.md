## ADDED Requirements

### Requirement: Usage history is mirrored to iCloud when sync is enabled
When Sync History via iCloud is enabled, the macOS app SHALL mirror usage-history snapshots to an iCloud file in the Tempo container.

#### Scenario: Local append writes to iCloud mirror
- **WHEN** a new `UsageSnapshot` is appended while iCloud sync is enabled
- **THEN** the app writes updated history to the iCloud history file

#### Scenario: iCloud sync disabled prevents mirror writes
- **WHEN** Sync History via iCloud is disabled
- **THEN** local history continues to persist locally and no iCloud mirror write is attempted

### Requirement: Local and iCloud history converge by merge-and-dedupe
The system SHALL merge local and iCloud snapshot sets, dedupe equivalent snapshots, sort by timestamp, and prune to retention policy before persistence.

#### Scenario: Multi-Mac overlap
- **WHEN** local and iCloud files contain overlapping snapshots from different Macs
- **THEN** duplicate-equivalent snapshots are stored once in the merged result

#### Scenario: One side has additional snapshots
- **WHEN** either local or iCloud history has snapshots absent on the other side
- **THEN** the merged result includes the union of snapshots after pruning

### Requirement: iCloud sync failures do not block local history behavior
Failures reading/writing iCloud history SHALL NOT interrupt local history collection, chart rendering, or polling.

#### Scenario: iCloud unavailable
- **WHEN** iCloud container or history file is temporarily unavailable
- **THEN** local history append and save continue, and sync retries on future sync cycles

#### Scenario: iCloud returns after outage
- **WHEN** iCloud access becomes available again
- **THEN** the app resumes merge-and-mirror behavior without requiring app reinstall or data reset
