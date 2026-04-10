## REMOVED Requirements

### Requirement: TempoTheme provides design token colors
**Reason**: `TempoTheme` is replaced entirely by `ClaudeCodeTheme` as part of the Claude Code palette unification. The Graphite + Electric Violet palette is superseded by the official Claude Code terracotta + warm-neutral palette defined in `Shared/ClaudeCodeTheme.swift`.
**Migration**: Replace all `TempoTheme.*` references with the corresponding `ClaudeCodeTheme.*` token:
- `TempoTheme.background` → `ClaudeCodeTheme.background`
- `TempoTheme.surface` → `ClaudeCodeTheme.surface`
- `TempoTheme.card` → `ClaudeCodeTheme.card`
- `TempoTheme.accent` → `ClaudeCodeTheme.accent`
- `TempoTheme.accentLight` → `ClaudeCodeTheme.accentLight`
- `TempoTheme.accentMuted` → `ClaudeCodeTheme.accentMuted`
- `TempoTheme.textPrimary` → `ClaudeCodeTheme.textPrimary`
- `TempoTheme.textSecondary` → `ClaudeCodeTheme.textSecondary`
- `TempoTheme.textTertiary` → `ClaudeCodeTheme.textTertiary`
- `TempoTheme.progressTrack` → `ClaudeCodeTheme.progressTrack`
- `TempoTheme.success` → `ClaudeCodeTheme.success`
- `TempoTheme.warning` → `ClaudeCodeTheme.warning`
- `TempoTheme.critical` → `ClaudeCodeTheme.error`
- `TempoTheme.info` → `ClaudeCodeTheme.info`
- `TempoTheme.destructive` → `ClaudeCodeTheme.destructive`

Delete `Tempo macOS/TempoTheme.swift` after all references are migrated.

### Requirement: TempoTheme is scoped to macOS target
**Reason**: Superseded by `ClaudeCodeTheme` which lives in `Shared/` and is available to all platforms.
**Migration**: No scoping action needed. `ClaudeCodeTheme` in `Shared/` is automatically available to all targets.
