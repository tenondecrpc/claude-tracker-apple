## ADDED Purpose

Define iOS and macOS WidgetKit experiences for Tempo that present usage state, freshness, and deep-link navigation from a shared snapshot model.

## ADDED Requirements

### Requirement: Tempo provides iOS and macOS usage widgets
Tempo SHALL provide WidgetKit widgets for both the iOS app and the macOS app. The first release SHALL include three widget variants inspired by the provided references:
- a small ring widget
- a medium summary widget with horizontal progress bars
- a small compact metrics widget with stacked values

#### Scenario: Small ring widget is available
- **WHEN** the user adds a Tempo widget in a small system family
- **THEN** a ring-focused widget variant is available that emphasizes current session usage

#### Scenario: Medium summary widget is available
- **WHEN** the user adds a Tempo widget in a medium system family
- **THEN** a wide summary widget is available that shows session and weekly progress bars

#### Scenario: Small compact metrics widget is available
- **WHEN** the user adds a Tempo widget in a small system family
- **THEN** a compact metrics widget is available that prioritizes numeric session and weekly values over the ring

### Requirement: Widgets render from a shared widget snapshot
Tempo widgets SHALL render from a host-app-managed widget snapshot stored in shared App Group storage. Widgets SHALL NOT read directly from the Anthropic API, iCloud documents, or `NSMetadataQuery`.

#### Scenario: Widget provider loads latest snapshot
- **WHEN** the widget timeline provider creates an entry
- **THEN** it reads the latest available widget snapshot from shared App Group storage

#### Scenario: No direct sync work in widget extension
- **WHEN** the widget extension renders content
- **THEN** it uses only the shared snapshot and local placeholder data, without starting its own network or iCloud read flow

### Requirement: Widgets show core Tempo usage metrics
Each widget variant SHALL display the latest current-session utilization and weekly utilization from the shared widget snapshot. Medium and compact widgets SHALL also display reset timing context, and widgets SHALL display extra-usage information when that data is present in the snapshot.

#### Scenario: Summary widget shows both percentages
- **WHEN** the snapshot contains `utilization5h = 0.45` and `utilization7d = 0.67`
- **THEN** the summary widget displays 45% for the current session and 67% for the weekly limit

#### Scenario: Reset timing appears in dense text layouts
- **WHEN** the snapshot includes `resetAt5h` and `resetAt7d`
- **THEN** the medium and compact widgets display reset timing labels for the session and weekly metrics

#### Scenario: Extra usage shown when enabled
- **WHEN** the snapshot includes enabled extra-usage values
- **THEN** at least one widget variant displays the extra-usage summary without hiding the core session and weekly metrics

### Requirement: Widgets expose waiting, stale, and mock states
Tempo widgets SHALL communicate data freshness. If no valid widget snapshot exists, widgets SHALL render an empty or waiting state. If the snapshot is stale, widgets SHALL show that the data is old. If the snapshot is based on mock data, widgets SHALL visibly indicate mock state.

#### Scenario: Waiting state with no snapshot
- **WHEN** the widget provider cannot find any valid widget snapshot
- **THEN** the widget displays a waiting or setup state instead of empty metric placeholders

#### Scenario: Stale state shown
- **WHEN** the widget snapshot exceeds the app-defined freshness threshold
- **THEN** the widget displays a stale-data indicator or "updated ago" label

#### Scenario: Mock state shown
- **WHEN** the widget snapshot has `isMocked = true`
- **THEN** the widget shows a visible mock indicator

### Requirement: Widget taps open Tempo in a relevant destination
Tempo widgets SHALL attach a deep link that opens the host app in a relevant destination for the widget content.

#### Scenario: iOS widget opens dashboard
- **WHEN** the user taps a Tempo widget on iOS
- **THEN** Tempo opens to the dashboard experience

#### Scenario: macOS widget opens stats detail
- **WHEN** the user taps a Tempo widget on macOS
- **THEN** Tempo opens the relevant stats or detail window instead of only foregrounding the app shell
