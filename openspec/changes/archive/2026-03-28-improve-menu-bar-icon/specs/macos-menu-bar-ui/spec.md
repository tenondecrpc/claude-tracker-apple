## ADDED Requirements

### Requirement: Dynamic menu bar icon based on usage
The system SHALL display a dynamic indicator graph as the menu bar icon when the user is authenticated and usage data is available. The indicator SHALL visually represent the current percentage of token/credit usage. If the user is not authenticated or usage data is not yet available, the system SHALL display a static default icon.

#### Scenario: Display default icon when unauthenticated
- **WHEN** the user is not signed in
- **THEN** the menu bar displays the static default app icon

#### Scenario: Display indicator graph when authenticated with usage data
- **WHEN** the user is signed in and the poller has fetched usage data (e.g., utilization is at 45%)
- **THEN** the menu bar displays a dynamic indicator graph reflecting 45% usage

#### Scenario: Update indicator graph when usage changes
- **WHEN** new usage data is polled and the utilization percentage changes
- **THEN** the menu bar icon updates to reflect the new percentage

#### Scenario: Handle dark and light mode
- **WHEN** the system appearance changes between dark and light mode
- **THEN** the dynamic indicator graph icon adapts its colors to remain visible and native-looking (e.g., using template rendering)
