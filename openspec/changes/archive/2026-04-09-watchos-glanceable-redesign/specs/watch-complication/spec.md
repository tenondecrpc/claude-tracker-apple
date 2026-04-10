## ADDED Requirements

### Requirement: AccessoryCircular gauge complication
The watch app SHALL provide a WidgetKit complication using the `accessoryCircular` family that displays a `Gauge` showing the current 5h utilization (0.0–1.0). The gauge SHALL use `AccessoryCircularGaugeStyle` with the utilization percentage as center text.

#### Scenario: Gauge at 42% utilization
- **WHEN** the stored `utilization5h` is 0.42
- **THEN** the complication displays a circular gauge filled to 42% with "42" as center text

#### Scenario: Gauge at 100% utilization
- **WHEN** the stored `utilization5h` is 1.0
- **THEN** the complication displays a full circular gauge with "100" as center text

#### Scenario: Gauge at 0% utilization
- **WHEN** the stored `utilization5h` is 0.0
- **THEN** the complication displays an empty gauge with "0" as center text

### Requirement: Color-coded gauge tint
The gauge fill color SHALL match the status thresholds: green (< 0.6), amber (0.6–0.85), red (>= 0.85). Colors SHALL use the watchOS rendering of `ClaudeCodeTheme` status tokens.

#### Scenario: Low utilization tint
- **WHEN** `utilization5h` is 0.30
- **THEN** the gauge fill is green

#### Scenario: High utilization tint
- **WHEN** `utilization5h` is 0.90
- **THEN** the gauge fill is red

### Requirement: Data shared via AppGroup UserDefaults
The complication SHALL read `utilization5h` from a shared `AppGroup` `UserDefaults` key `"complication_utilization5h"` (type `Double`). The watch app's `WatchSessionReceiver` SHALL write this value every time a new `UsageState` is received.

#### Scenario: Data written on receive
- **WHEN** `WatchSessionReceiver` processes a new `UsageState` with `utilization5h: 0.65`
- **THEN** `UserDefaults(suiteName: appGroupId)?.set(0.65, forKey: "complication_utilization5h")` is called

#### Scenario: Widget reads shared data
- **WHEN** the widget timeline provider creates a timeline entry
- **THEN** it reads `utilization5h` from `UserDefaults(suiteName: appGroupId)`

#### Scenario: No data stored yet
- **WHEN** the shared `UserDefaults` has no value for the key
- **THEN** the complication displays 0% gauge

### Requirement: Timeline refresh on data update
After writing new utilization data to `AppGroup`, the watch app SHALL call `WidgetCenter.shared.reloadAllTimelines()` to trigger a complication refresh.

#### Scenario: Refresh triggered after update
- **WHEN** `WatchSessionReceiver` writes a new `utilization5h` value
- **THEN** `WidgetCenter.shared.reloadAllTimelines()` is called immediately after the write

### Requirement: Static timeline with single entry
The widget timeline provider SHALL return a single `TimelineEntry` with the current utilization and a `.never` reload policy. Refreshes are driven by the app calling `reloadAllTimelines()` rather than scheduled polling.

#### Scenario: Timeline entry created
- **WHEN** the widget system requests a timeline
- **THEN** the provider returns exactly one entry with the current date and stored utilization, with `.never` policy
