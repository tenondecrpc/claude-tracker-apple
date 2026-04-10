## ADDED Requirements

### Requirement: TempoTheme provides design token colors
A `TempoTheme` enum (no cases, pure namespace) SHALL be defined in `Tempo macOS/TempoTheme.swift` and SHALL expose static `Color` properties for each design token:
- `background`: #19191C (warm charcoal, RGB 0.098/0.098/0.110)
- `surface`: #222226 (elevated surface, RGB 0.133/0.133/0.149)
- `card`: #26262B (card background, RGB 0.149/0.149/0.169)
- `accent`: #7B4DED (electric violet, RGB 0.486/0.302/0.929)
- `accentLight`: #9B76F9 (lighter violet, RGB 0.608/0.463/0.976)
- `accentMuted`: accent at 15% opacity
- `textPrimary`: #EEEEEF (near-white, RGB 0.933/0.933/0.953)
- `textSecondary`: #888892 (muted gray, RGB 0.533/0.533/0.573)
- `textTertiary`: #5F5F68 (dim gray, RGB 0.373/0.373/0.408)
- `progressTrack`: #333339 (track background, RGB 0.200/0.200/0.224)
- `success`: #4CC28D (teal-green, RGB 0.298/0.761/0.553)
- `warning`: #F9BB3B (amber, RGB 0.976/0.733/0.231)
- `critical`: #EF5363 (rose-red, RGB 0.937/0.325/0.388)
- `info`: #4D99E0 (sky blue, RGB 0.302/0.600/0.878)
- `destructive`: #EF5363 (alias of critical, for quit/destructive actions)

#### Scenario: Colors match hex values
- **WHEN** a view references `TempoTheme.accent`
- **THEN** the rendered color matches #7B4DED (electric violet)

#### Scenario: Enum cannot be instantiated
- **WHEN** code attempts to create a `TempoTheme` instance
- **THEN** compilation fails (no cases, no init)

### Requirement: TempoTheme is scoped to macOS target
The `TempoTheme.swift` file SHALL live in `Tempo macOS/` and SHALL NOT be placed in `Shared/`, since it is specific to the macOS visual design.

#### Scenario: Theme not available in iOS or watchOS
- **WHEN** the iOS or watchOS target is compiled
- **THEN** `TempoTheme` is not included in the build

### Requirement: TempoTheme replaces ClaudeTheme entirely
`ClaudeTheme.swift` SHALL be deleted. All views in the macOS target that previously referenced `ClaudeTheme.*` SHALL reference the corresponding `TempoTheme.*` token instead. No `ClaudeTheme` reference SHALL remain in any compiled Swift file.

#### Scenario: No ClaudeTheme references compile
- **WHEN** the macOS target is built after the migration
- **THEN** there are zero compile errors related to `ClaudeTheme` not being found

#### Scenario: Consistent token mapping
- **WHEN** a view previously used `ClaudeTheme.accent` (coral #E07850)
- **THEN** it now uses `TempoTheme.accent` (violet #7B4DED) as the primary brand color
