## ADDED Requirements

### Requirement: Preferences tab displays settings in grouped card sections
The Preferences tab in the detail window SHALL display all app settings organized into three card sections:

**General** card:
- Launch at Login (icon: `power`, title, subtitle, toggle)
- Show Percentage in Menu Bar (icon: `percent`, title, subtitle, toggle)
- 24-Hour Time (icon: `clock.arrow.2.circlepath`, title, subtitle, toggle)

**Data & Sync** card:
- Sync History via iCloud (icon: `icloud`, title, subtitle, toggle)
- Service Status Monitoring (icon: `dot.radiowaves.left.and.right`, title, subtitle, toggle)

**Account** card:
- Account email displayed in `.callout` in `TempoTheme.textSecondary`
- "Sign Out" button in `TempoTheme.critical` color, `.callout` weight

Each card uses `TempoTheme.card` background, 12pt corner radius, 24pt internal padding, with section header labels in `TempoTheme.textSecondary` `.subheadline.weight(.semibold)`.

#### Scenario: Preferences tab shows three grouped sections
- **WHEN** the Preferences tab is selected
- **THEN** three card groups are visible: General (3 rows), Data & Sync (2 rows), Account (email + sign out)

#### Scenario: Toggle state persists
- **WHEN** the user changes a toggle in the Preferences tab and reopens the window
- **THEN** the toggle shows the same value that was set

### Requirement: Gear icon settings popover is removed
The gear button and its associated settings popover (previously in the `StatsDetailView` header) SHALL be completely removed. All settings functionality SHALL be available exclusively through the Preferences tab.

#### Scenario: No gear icon in header
- **WHEN** the detail window header is rendered
- **THEN** there is no gear or settings icon button visible

#### Scenario: Settings still functional
- **WHEN** the user navigates to the Preferences tab
- **THEN** all five previously-available toggles are accessible and functional

### Requirement: Preferences tab max width is constrained for readability
The Preferences tab content SHALL be constrained to a maximum width of 560pt and centered horizontally within the window, to prevent card sections from stretching excessively on wider windows.

#### Scenario: Cards don't stretch beyond 560pt
- **WHEN** the detail window is resized to 1200pt wide
- **THEN** the Preferences tab cards remain at most 560pt wide, centered in the window
