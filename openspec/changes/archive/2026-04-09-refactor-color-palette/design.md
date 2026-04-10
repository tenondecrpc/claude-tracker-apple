## Context

The app has two color systems that evolved independently: `Theme.swift` in `Shared/` (Claude terracotta palette, consumed only by watchOS) and `TempoTheme.swift` in `Tempo macOS/` (purple/cool-gray palette, consumed by 26 macOS files). Neither matches the official Claude Code branding from Anthropic's `palette.ts`. The `AccentColor.colorset` files across all 4 targets are empty placeholders.

The official Claude Code theme provides complete dark and light palettes with warm terracotta accents, warm-neutral backgrounds, and muted status colors — a cohesive system ready to adopt.

## Goals / Non-Goals

**Goals:**
- Single color source of truth in `Shared/ClaudeCodeTheme.swift` consumed by all platforms
- Full dark mode palette matching official Claude Code Dark theme
- Full light mode palette matching official Claude Code Light theme
- User-controllable appearance mode (dark/light/system, default dark) via Preferences
- Calmer, brand-aligned status colors
- `highlight` token (#9B87F5) for 7d ring and emphasis elements

**Non-Goals:**
- Custom user-defined color themes
- Per-platform color overrides (all platforms share the same tokens)
- Syntax highlighting or code editor theming
- Animated color transitions between modes

## Decisions

### 1. Unified enum in Shared/ (not Color extensions)

**Decision**: Use `enum ClaudeCodeTheme` with static computed properties that resolve based on a stored appearance mode, rather than `Color` extensions.

**Why**: An enum namespace avoids polluting `Color`'s namespace, provides clear call-site semantics (`ClaudeCodeTheme.accent` vs `Color.claudeAccent`), and matches the existing `TempoTheme` pattern that 26 files already use — minimizing migration friction.

**Alternatives considered**:
- `Color` extensions (current `Theme.swift` pattern) — unclear namespace, harder to search/refactor
- Asset catalog colors — no runtime theme switching, can't encode light/dark logic in code

### 2. Appearance resolution via static mode property

**Decision**: `ClaudeCodeTheme` reads appearance mode from `MacSettingsStore.shared.appearanceMode` (an enum: `.dark`, `.light`, `.system`) and resolves colors at access time. On watchOS/iOS where `MacSettingsStore` doesn't exist, always resolve to dark.

**Why**: Avoids passing `colorScheme` through every call site. The `preferredColorScheme` modifier on the root view forces SwiftUI to match, so the static resolution stays in sync. Platform-conditional compilation (`#if os(macOS)`) keeps it simple.

**Alternatives considered**:
- `@Environment(\.colorScheme)` at every call site — too invasive, requires passing through 26+ files
- Two separate enum cases (`.dark`, `.light`) with manual switching — more boilerplate, easy to forget

### 3. Appearance mode preference: 3-state enum

**Decision**: `AppearanceMode` enum with `.dark` (default), `.light`, `.system`. Stored in UserDefaults via `MacSettingsStore`.

**Why**: `.system` respects macOS system appearance for users who want it. Default `.dark` matches the brand priority. Three states cover all reasonable preferences without overcomplicating.

### 4. Token naming follows Claude Code palette.ts

**Decision**: Token names map directly to the Claude Code theme source:

| Token | Dark | Light |
|---|---|---|
| `background` | #141413 | #FAF9F5 |
| `surface` | #1F1D1A | #F0EEE6 |
| `card` | #2B2A27 | #EAE7DF |
| `accent` | #C96442 | #CC785C |
| `accentLight` | #D97757 | #C96442 |
| `accentMuted` | #C96442@15% | #CC785C@15% |
| `textPrimary` | #EAE7DF | #1A1917 |
| `textSecondary` | #A9A39A | #6B665F |
| `textTertiary` | #6B665F | #8D877D |
| `border` | #4A473F | #D9D5CC |
| `success` | #9ACA86 | #2E7C4C |
| `warning` | #E8C96B | #8A6220 |
| `error` | #D47563 | #A84B3A |
| `info` | #61AAF2 | #207FDE |
| `highlight` | #9B87F5 | #6A5BCC |
| `destructive` | #D47563 | #A84B3A |
| `progressTrack` | #4A473F | #D9D5CC |
| `ringTrack` | white@15% | black@10% |
| `ringTrackInner` | white@10% | black@8% |

### 5. Migration: mechanical find-and-replace

**Decision**: Replace `TempoTheme.` → `ClaudeCodeTheme.` across all macOS files. Replace `Color.claude*` → `ClaudeCodeTheme.*` in watchOS. Token names are kept identical where possible (`accent`, `surface`, `card`, `textPrimary`, etc.) to minimize diff size.

**Mapping for renamed tokens**:
- `TempoTheme.critical` → `ClaudeCodeTheme.error`
- `TempoTheme.destructive` → `ClaudeCodeTheme.destructive` (same name, new color)
- `Color.claudeAccent` → `ClaudeCodeTheme.accent`
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

### 6. AccentColor.colorset populated with #C96442

**Decision**: All 4 target asset catalogs get the terracotta accent in both light and dark appearance slots.

**Why**: This affects system-level tinting (buttons, links, focus rings) and ensures consistency even in native controls that don't read `ClaudeCodeTheme`.

## Risks / Trade-offs

- **[Hardcoded dark on watchOS/iOS]** → Acceptable: watchOS always displays dark; iOS is a passthrough app with minimal UI. Can add appearance support to these targets later if needed.
- **[Static resolution vs Environment]** → If `MacSettingsStore.shared` and `preferredColorScheme` ever get out of sync, colors could mismatch. Mitigation: the preference change triggers a root view update that sets both simultaneously.
- **[Calmer status colors may reduce urgency]** → The softer red (#D47563 vs #EF5363) is less alarming. Mitigation: ring animation and pulse dot still provide visual urgency cues beyond just color.
- **[26-file migration]** → Large diff but mechanical. Mitigation: token names are preserved where possible, making the change a find-and-replace operation.
