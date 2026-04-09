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
