## ADDED Requirements

### Requirement: Menu bar icon is a pulse dot with arc ring
The macOS menu bar icon SHALL be a programmatically rendered 18×18pt template `NSImage` containing:
- A **track circle**: center (9,9), radius 6pt, lineWidth 1.5pt, drawn at 30% opacity (represents 0–100% range)
- An **arc fill**: same center and radius, starting at −90° (12 o'clock), sweeping clockwise to `utilization5h × 360° − 90°`, lineWidth 1.5pt, `lineCap .round`, drawn at full opacity
- A **center dot**: filled circle, 5×5pt, centered at (6.5, 6.5)

The image SHALL have `isTemplate = true` so it adapts automatically to light and dark menu bar appearances.

When `utilization5h` is 0, only the track circle and center dot are drawn (no arc fill).

#### Scenario: 50% session utilization
- **WHEN** `utilization5h = 0.50`
- **THEN** the arc fill covers exactly a half-circle (180°) from the top, sweeping clockwise

#### Scenario: 0% session utilization
- **WHEN** `utilization5h = 0.0`
- **THEN** only the faint track ring and center dot are visible; no arc fill is drawn

#### Scenario: 100% session utilization
- **WHEN** `utilization5h = 1.0`
- **THEN** the arc fill covers the full circle (360°), visually merging with the track ring

#### Scenario: Template image adapts to menu bar appearance
- **WHEN** the system uses a dark menu bar
- **THEN** the icon renders in white; when the menu bar is light, it renders in black

### Requirement: Pulse dot icon replaces signal-strength bars icon
The existing `NSImage.usageBar(percentage:)` signal-strength bars implementation SHALL be removed and replaced by the pulse dot renderer. The file `DynamicMenuBarIconView.swift` SHALL be renamed to `MenuBarIconView.swift`.

#### Scenario: No signal bars in menu bar
- **WHEN** the app is running
- **THEN** the menu bar shows the pulse dot icon, not three vertical bars

### Requirement: Optional percentage text preserved
When `showPercentage` is enabled, the numeric session percentage text SHALL continue to appear to the right of the pulse dot icon, using the same `.system(size: 12, weight: .medium, design: .monospaced)` font.

#### Scenario: Percentage text shown alongside pulse dot
- **WHEN** `showPercentage = true` and `utilization5h = 0.42`
- **THEN** the menu bar shows the pulse dot followed by "42%"
