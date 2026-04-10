## ADDED Requirements

### Requirement: ClaudeTheme provides design token colors
A `ClaudeTheme` enum (no cases, pure namespace) SHALL expose static `Color` properties for each design token:
- `background`: #1E2A3A (dark navy)
- `surface`: #263347 (slightly lighter navy)
- `accent`: #E07850 (coral/salmon)
- `textPrimary`: #FFFFFF (white)
- `textSecondary`: #8899AA (muted blue-gray)
- `progressTrack`: #3A4A5C (dark track)
- `destructive`: #E05050 (red, for quit/destructive actions)
- `lockIcon`: #5B9BD5 (light blue)

#### Scenario: Colors match hex values
- **WHEN** a view references `ClaudeTheme.accent`
- **THEN** the rendered color matches #E07850

#### Scenario: Enum cannot be instantiated
- **WHEN** code attempts to create a `ClaudeTheme` instance
- **THEN** compilation fails (no cases, no init)

### Requirement: ClaudeTheme is scoped to macOS target
The `ClaudeTheme` file SHALL live in the `Tempo macOS/` directory, not in `Shared/`, since it is specific to the macOS visual design.

#### Scenario: Theme not available in iOS or watchOS
- **WHEN** the iOS or watchOS target is compiled
- **THEN** `ClaudeTheme` is not included in the build
