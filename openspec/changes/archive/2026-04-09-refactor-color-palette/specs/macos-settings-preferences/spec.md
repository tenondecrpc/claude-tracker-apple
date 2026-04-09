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
- Show Percentage in Menu Bar
- 24-Hour Time
- Service Status Monitoring
- Sync History via iCloud
- **Appearance Mode** (Dark / Light / System, default Dark)

The settings surface SHALL be the Preferences tab of the stats detail window, organized in grouped card sections. The previous gear-icon floating popover is removed.

#### Scenario: User opens settings via Preferences tab
- **WHEN** the user opens the stats detail window and clicks the "Preferences" tab
- **THEN** the settings UI displays all six preferences (five toggles plus one segmented picker) with their current persisted values, organized in grouped cards

#### Scenario: Toggle values persist across relaunch
- **WHEN** the user changes one or more settings and relaunches the app
- **THEN** the same values are restored and used by the app
