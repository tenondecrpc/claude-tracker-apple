## ADDED Requirements

### Requirement: ClaudeCodeTheme provides unified design token colors
A `ClaudeCodeTheme` enum (no cases, pure namespace) SHALL be defined in `Shared/ClaudeCodeTheme.swift` and SHALL expose static computed `Color` properties that resolve to dark or light mode values based on the current appearance mode. The dark mode palette SHALL be the default and SHALL match the official Claude Code Dark theme from `palette.ts`:

**Dark Mode Tokens:**
- `background`: #141413 (RGB 0.078/0.078/0.075)
- `surface`: #1F1D1A (RGB 0.122/0.114/0.102)
- `card`: #2B2A27 (RGB 0.169/0.165/0.153)
- `accent`: #C96442 (RGB 0.788/0.392/0.259)
- `accentLight`: #D97757 (RGB 0.851/0.467/0.341)
- `accentMuted`: accent at 15% opacity
- `textPrimary`: #EAE7DF (RGB 0.918/0.906/0.875)
- `textSecondary`: #A9A39A (RGB 0.663/0.639/0.604)
- `textTertiary`: #6B665F (RGB 0.420/0.400/0.373)
- `border`: #4A473F (RGB 0.290/0.278/0.247)
- `progressTrack`: #4A473F (RGB 0.290/0.278/0.247)
- `success`: #9ACA86 (RGB 0.604/0.792/0.525)
- `warning`: #E8C96B (RGB 0.910/0.788/0.420)
- `error`: #D47563 (RGB 0.831/0.459/0.388)
- `info`: #61AAF2 (RGB 0.380/0.667/0.949)
- `highlight`: #9B87F5 (RGB 0.608/0.529/0.961)
- `destructive`: #D47563 (alias of error)
- `ringTrack`: white at 15% opacity
- `ringTrackInner`: white at 10% opacity

**Light Mode Tokens:**
- `background`: #FAF9F5
- `surface`: #F0EEE6
- `card`: #EAE7DF
- `accent`: #CC785C
- `accentLight`: #C96442
- `accentMuted`: accent at 15% opacity
- `textPrimary`: #1A1917
- `textSecondary`: #6B665F
- `textTertiary`: #8D877D
- `border`: #D9D5CC
- `progressTrack`: #D9D5CC
- `success`: #2E7C4C
- `warning`: #8A6220
- `error`: #A84B3A
- `info`: #207FDE
- `highlight`: #6A5BCC
- `destructive`: #A84B3A
- `ringTrack`: black at 10% opacity
- `ringTrackInner`: black at 8% opacity

#### Scenario: Dark mode colors match hex values
- **WHEN** appearance mode is `.dark` and a view references `ClaudeCodeTheme.accent`
- **THEN** the rendered color matches #C96442 (terracotta)

#### Scenario: Light mode colors match hex values
- **WHEN** appearance mode is `.light` and a view references `ClaudeCodeTheme.accent`
- **THEN** the rendered color matches #CC785C (light terracotta)

#### Scenario: Enum cannot be instantiated
- **WHEN** code attempts to create a `ClaudeCodeTheme` instance
- **THEN** compilation fails (no cases, no init)

### Requirement: ClaudeCodeTheme is available to all platform targets
`Shared/ClaudeCodeTheme.swift` SHALL be placed in the `Shared/` directory and SHALL be available to macOS, iOS, watchOS, and watchOS Extension targets via `PBXFileSystemSynchronizedRootGroup`.

#### Scenario: Theme available on all platforms
- **WHEN** any target (macOS, iOS, watchOS, watchOS Extension) is compiled
- **THEN** `ClaudeCodeTheme` is included in the build and all tokens are accessible

### Requirement: Appearance mode resolves color variants
`ClaudeCodeTheme` SHALL resolve colors based on the current appearance mode:
- On macOS: read `MacSettingsStore.shared.appearanceMode` (`.dark`, `.light`, or `.system`)
- On watchOS/iOS: always resolve to dark mode
- When mode is `.system` on macOS: use `NSApp.effectiveAppearance` to determine dark vs light

#### Scenario: macOS dark mode (default)
- **WHEN** `MacSettingsStore.shared.appearanceMode` is `.dark`
- **THEN** all tokens resolve to their dark mode values

#### Scenario: macOS light mode
- **WHEN** `MacSettingsStore.shared.appearanceMode` is `.light`
- **THEN** all tokens resolve to their light mode values

#### Scenario: macOS system mode follows system appearance
- **WHEN** `MacSettingsStore.shared.appearanceMode` is `.system` and macOS is set to dark mode
- **THEN** all tokens resolve to their dark mode values

#### Scenario: watchOS always dark
- **WHEN** the watchOS target renders a view referencing `ClaudeCodeTheme.background`
- **THEN** the color resolves to #141413 regardless of any setting

### Requirement: AccentColor.colorset populated with terracotta
All 4 target `AccentColor.colorset` files SHALL be populated with #C96442 for both light and dark appearance variants.

#### Scenario: System controls use terracotta accent
- **WHEN** a native SwiftUI control (e.g., `Toggle`, `Button`) renders with the default accent color
- **THEN** the control tint matches #C96442

### Requirement: AppearanceMode enum for preference storage
An `AppearanceMode` enum SHALL be defined with cases `.dark`, `.light`, `.system`. It SHALL conform to `String`, `CaseIterable`, and `Codable`. The default value SHALL be `.dark`.

#### Scenario: Default appearance mode
- **WHEN** the app launches for the first time with no stored preference
- **THEN** appearance mode resolves to `.dark`

#### Scenario: Enum is persistable
- **WHEN** an `AppearanceMode` value is stored via `UserDefaults`
- **THEN** it can be restored correctly after app relaunch
