## REMOVED Requirements

### Requirement: ClaudeTheme provides design token colors
**Reason**: `ClaudeTheme` is replaced entirely by `TempoTheme` as part of the Tempo rebranding. The Navy + Terracotta color palette is superseded by the Graphite + Electric Violet palette defined in `TempoTheme.swift`.
**Migration**: Replace all `ClaudeTheme.*` references with the corresponding `TempoTheme.*` token:
- `ClaudeTheme.background` → `TempoTheme.background`
- `ClaudeTheme.surface` → `TempoTheme.surface`
- `ClaudeTheme.accent` → `TempoTheme.accent`
- `ClaudeTheme.textPrimary` → `TempoTheme.textPrimary`
- `ClaudeTheme.textSecondary` → `TempoTheme.textSecondary`
- `ClaudeTheme.progressTrack` → `TempoTheme.progressTrack`
- `ClaudeTheme.destructive` → `TempoTheme.destructive`
- `ClaudeTheme.lockIcon` → `TempoTheme.info`

Delete `ClaudeTracker macOS/ClaudeTheme.swift` after all references are migrated.

### Requirement: ClaudeTheme is scoped to macOS target
**Reason**: Superseded by `TempoTheme` which inherits the same scoping constraint.
**Migration**: `TempoTheme.swift` SHALL live in `ClaudeTracker macOS/` and is not included in iOS or watchOS builds. No action required beyond deleting `ClaudeTheme.swift`.
