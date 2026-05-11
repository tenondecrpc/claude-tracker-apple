## ADDED Requirements

### Requirement: Watch sends RequestFreshRelay message on scene activation
When the watch app scene transitions to `.active` and an `activeAccountId` is known, the watch SHALL send a `sendMessage` with payload `["type": "RequestFreshRelay"]` to the iPhone via WatchConnectivity. The message SHALL NOT be sent when `activeAccountId` is nil or when `hasNoActiveAccount` is true.

#### Scenario: Scene becomes active with known account
- **WHEN** the watch app scene transitions to `.active` and `activeAccountId` is non-nil
- **THEN** the watch sends `["type": "RequestFreshRelay"]` via `WCSession.default.sendMessage`

#### Scenario: Scene becomes active without account
- **WHEN** the watch app scene transitions to `.active` and `activeAccountId` is nil
- **THEN** no message is sent

#### Scenario: Scene becomes active with NoActiveAccount
- **WHEN** the watch app scene transitions to `.active` and `hasNoActiveAccount` is true
- **THEN** no message is sent

### Requirement: Watch sends RequestFreshRelay on user-initiated refresh tap
When the user taps the refresh control and the watch is not already in `.inProgress` state, the watch SHALL send a `sendMessage` with payload `["type": "RequestFreshRelay"]` to the iPhone.

#### Scenario: User taps refresh while idle
- **WHEN** the user taps the refresh control and state is `.idle`
- **THEN** the watch sends `["type": "RequestFreshRelay"]` and transitions to `.inProgress`

#### Scenario: User taps refresh while already in progress
- **WHEN** the user taps the refresh control and state is `.inProgress`
- **THEN** no additional message is sent

### Requirement: Watch checks reachability before sending
Before sending `RequestFreshRelay`, the watch SHALL check `WCSession.default.isReachable`. If not reachable, the coordinator SHALL immediately transition to `.error` with reason "iPhone not reachable" without attempting the send.

#### Scenario: iPhone reachable
- **WHEN** `isReachable` is true
- **THEN** the message is sent normally

#### Scenario: iPhone not reachable
- **WHEN** `isReachable` is false
- **THEN** the coordinator transitions to `.error("iPhone not reachable")` without calling `sendMessage`

### Requirement: Watch transitions to success when a fresh relay arrives
The coordinator SHALL observe `TokenStore` for a new `UsageState` application (timestamp newer than when the request was sent). When observed, the coordinator transitions from `.inProgress` to `.idle`. A timeout of 10 seconds transitions to `.error` if no fresh relay arrives.

#### Scenario: Fresh relay arrives within timeout
- **WHEN** a `UsageState` is applied to `TokenStore` within 10 seconds of the request
- **THEN** the coordinator transitions to `.idle`

#### Scenario: Timeout expires without fresh relay
- **WHEN** 10 seconds pass after sending `RequestFreshRelay` without a new `UsageState` arriving
- **THEN** the coordinator transitions to `.error("No response from iPhone")`

#### Scenario: sendMessage error handler fires
- **WHEN** `sendMessage` calls its error handler (e.g., session deactivated)
- **THEN** the coordinator transitions to `.error` with a user-friendly reason
