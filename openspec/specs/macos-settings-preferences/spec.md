## MODIFIED Requirements

### Requirement: Settings surface exposes persistent toggles for enabled features
The macOS app SHALL provide a settings surface that exposes the following toggles with persisted values:
- Launch at Login
- Show Percentage in Menu Bar
- 24-Hour Time
- Service Status Monitoring
- Sync History via iCloud

The settings surface SHALL be the Preferences tab of the stats detail window, organized in grouped card sections. The previous gear-icon floating popover is removed.

#### Scenario: User opens settings via Preferences tab
- **WHEN** the user opens the stats detail window and clicks the "Preferences" tab
- **THEN** the settings UI displays all five toggles with their current persisted values, organized in grouped cards

#### Scenario: Toggle values persist across relaunch
- **WHEN** the user changes one or more settings and relaunches the app
- **THEN** the same values are restored and used by the app

### Requirement: Launch at Login toggle controls login item registration
The system SHALL manage launch-at-login state through `SMAppService.mainApp` when the app location supports login item management.

#### Scenario: Enable launch at login
- **WHEN** the user enables Launch at Login and the app is in a supported install location
- **THEN** the app registers itself with `SMAppService.mainApp` and persists the enabled state

#### Scenario: Unsupported install location
- **WHEN** the app is not in a supported install location for `SMAppService` management
- **THEN** the Launch at Login toggle is disabled and the UI shows helper text explaining the constraint

### Requirement: Show Percentage preference controls menu bar percentage label
The system SHALL conditionally show the percentage text next to the menu bar pulse dot icon according to the Show Percentage preference.

#### Scenario: Percentage enabled
- **WHEN** Show Percentage in Menu Bar is enabled and authenticated usage is available
- **THEN** the menu bar item includes the numeric session percentage text next to the pulse dot icon

#### Scenario: Percentage disabled
- **WHEN** Show Percentage in Menu Bar is disabled
- **THEN** the menu bar item shows the pulse dot icon only and omits percentage text

### Requirement: 24-Hour Time preference controls reset-time formatting
The system SHALL format reset-time labels according to the 24-Hour Time preference.

#### Scenario: 24-hour format enabled
- **WHEN** 24-Hour Time is enabled
- **THEN** reset-time labels use 24-hour output (for example `14:30`)

#### Scenario: 24-hour format disabled
- **WHEN** 24-Hour Time is disabled
- **THEN** reset-time labels use 12-hour output with meridiem (for example `2:30 PM`)
