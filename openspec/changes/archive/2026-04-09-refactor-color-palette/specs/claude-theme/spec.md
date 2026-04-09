## REMOVED Requirements

### Requirement: ClaudeTheme provides design token colors
**Reason**: The legacy `Color.claude*` extensions in `Shared/Theme.swift` are replaced by `ClaudeCodeTheme` tokens. The old terracotta palette is superseded by the official Claude Code palette with updated hex values.
**Migration**: Replace all `Color.claude*` references with the corresponding `ClaudeCodeTheme.*` token:
- `Color.claudeAccent` → `ClaudeCodeTheme.accent`
- `Color.claudeAccentDark` → `ClaudeCodeTheme.accent` (dark variant absorbed)
- `Color.claudeAccentLight` → `ClaudeCodeTheme.accentLight`
- `Color.claudeBgDeep` → `ClaudeCodeTheme.background`
- `Color.claudeBgElevated` → `ClaudeCodeTheme.surface`
- `Color.claudeBgSurface` → `ClaudeCodeTheme.card`
- `Color.claudeBorder` → `ClaudeCodeTheme.border`
- `Color.claudeTextPrimary` → `ClaudeCodeTheme.textPrimary`
- `Color.claudeTextSecondary` → `ClaudeCodeTheme.textSecondary`
- `Color.claudeTextTertiary` → `ClaudeCodeTheme.textTertiary`
- `Color.claudeGreen` → `ClaudeCodeTheme.success`
- `Color.claudeYellow` → `ClaudeCodeTheme.warning`
- `Color.claudeRed` → `ClaudeCodeTheme.error`
- `Color.claudeBlue` → `ClaudeCodeTheme.highlight`
- `Color.claudeRingTrack` → `ClaudeCodeTheme.ringTrack`
- `Color.claudeRingTrackInner` → `ClaudeCodeTheme.ringTrackInner`

Delete `Shared/Theme.swift` after all references are migrated.

### Requirement: ClaudeTheme is scoped to macOS target
**Reason**: Superseded by `ClaudeCodeTheme` which lives in `Shared/` and serves all platforms with the same tokens.
**Migration**: No action needed. `ClaudeCodeTheme` in `Shared/` auto-includes in all targets via `PBXFileSystemSynchronizedRootGroup`.
