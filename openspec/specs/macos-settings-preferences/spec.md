## ADDED Requirements

### Requirement: Appearance mode preference controls app color scheme
The macOS app SHALL expose an Appearance Mode preference in the Preferences panel with three options: Dark (default), Light, and System. The preference SHALL be stored in `MacSettingsStore` as `appearanceMode` and SHALL control which `ClaudeCodeTheme` color variant is rendered.

#### Scenario: Default appearance is dark
- **WHEN** the app launches for the first time with no stored preference
- **THEN** the appearance mode is `.dark` and all `ClaudeCodeTheme` tokens resolve to dark mode values

#### Scenario: User switches to light mode
- **WHEN** the user selects "Light" in the appearance mode preference
- **THEN** all `ClaudeCodeTheme` tokens resolve to light mode values and the UI re-renders immediately

#### Scenario: User selects system mode
- **WHEN** the user selects "System" in the appearance mode preference
- **THEN** the app follows the macOS system appearance setting (dark or light)

#### Scenario: Preference persists across relaunch
- **WHEN** the user sets appearance mode to "Light" and relaunches the app
- **THEN** the appearance mode is restored to "Light" on next launch

### Requirement: Appearance mode toggle uses segmented picker
The appearance mode preference SHALL be rendered as a segmented `Picker` with three options: Dark, Light, System. It SHALL be placed in the Preferences panel alongside existing toggles.

#### Scenario: Picker displays three segments
- **WHEN** the user views the Preferences panel
- **THEN** an "Appearance" row displays a segmented picker with "Dark", "Light", and "System" options

#### Scenario: Picker reflects current mode
- **WHEN** the current appearance mode is `.dark`
- **THEN** the "Dark" segment is selected in the picker

## MODIFIED Requirements

### Requirement: Settings surface exposes persistent toggles for enabled features
The macOS app SHALL provide a settings surface that exposes the following toggles with persisted values:
- Launch at Login
- **5-Hour Window** group:
  - Show Percentage
  - Show Reset Time
- **7-Day Window** group:
  - Show Percentage
  - Show Reset Time
- **Extra Usage** group:
  - Show Credits
- 24-Hour Time
- Service Status Monitoring
- Sync History via iCloud
- **Appearance Mode** (Dark / Light / System, default Dark)

The settings surface SHALL be the Preferences tab of the stats detail window, organized in grouped card sections. The previous single "Show Percentage in Menu Bar" toggle is replaced by the five menu bar segment toggles above, organized under a "Menu Bar Display" card with sub-groups.

#### Scenario: User opens settings via Preferences tab
- **WHEN** the user opens the stats detail window and clicks the "Preferences" tab
- **THEN** the settings UI displays all toggles organized in grouped cards, with menu bar toggles under "Menu Bar Display" grouped by time window

#### Scenario: Toggle values persist across relaunch
- **WHEN** the user changes one or more settings and relaunches the app
- **THEN** the same values are restored and used by the app

#### Scenario: All menu bar toggles default to off
- **WHEN** the app launches for the first time or upgrades from a version without the new toggles
- **THEN** all five menu bar segment toggles default to false, showing only the pulse dot icon

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
