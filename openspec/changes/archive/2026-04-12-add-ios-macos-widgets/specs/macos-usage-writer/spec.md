## ADDED Purpose

Ensure macOS publishes reliable widget snapshots from poll results so desktop widgets stay updated without direct API access.

## ADDED Requirements

### Requirement: macOS writes widget snapshot after successful usage polls
After a successful macOS usage poll, the app SHALL derive a widget snapshot from the latest `UsageState` and write it to shared App Group storage for the macOS widget extension.

#### Scenario: Widget snapshot written after poll success
- **WHEN** the macOS poller receives a valid usage response and updates `latestUsage`
- **THEN** the app writes a corresponding widget snapshot to the macOS widget App Group storage

#### Scenario: Snapshot timestamp matches successful poll
- **WHEN** the app writes a widget snapshot after a successful poll
- **THEN** the snapshot records the successful poll time as its freshness timestamp

### Requirement: macOS reloads widget timelines only after valid snapshot writes
The macOS app SHALL request widget timeline reloads only after it has successfully written a valid widget snapshot. Failed polls SHALL NOT clear the previous valid widget snapshot.

#### Scenario: Widget timelines reloaded after valid write
- **WHEN** the app successfully writes a new widget snapshot
- **THEN** it calls WidgetKit reload APIs for Tempo's macOS widget kinds

#### Scenario: Failed poll preserves last valid widget content
- **WHEN** a macOS usage poll fails because of auth, rate limit, or network error
- **THEN** the previous valid widget snapshot remains in shared storage and is not deleted or overwritten
