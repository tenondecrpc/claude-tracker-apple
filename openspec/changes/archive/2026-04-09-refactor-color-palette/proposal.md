## Why

The app currently has two disconnected color systems: `Theme.swift` (Shared/, used only by watchOS) with a Claude terracotta palette, and `TempoTheme.swift` (macOS-only) with a purple/cool-gray palette. Neither matches the official Claude Code branding. This creates visual inconsistency across platforms and diverges from Anthropic's identity. Unifying to the official Claude Code Dark palette (sourced from `palette.ts`) brings brand alignment, cross-platform consistency, and a single maintainable color source of truth.

## What Changes

- **BREAKING**: Replace `TempoTheme.*` enum (21 tokens) with `ClaudeCodeTheme.*` — all 26 macOS files must update references
- **BREAKING**: Replace `Color.claude*` extensions (15 tokens) with `ClaudeCodeTheme.*` — watchOS ContentView must update references
- Create unified `Shared/ClaudeCodeTheme.swift` with full dark + light mode palettes from the official Claude Code theme
- Delete `Shared/Theme.swift` and `Tempo macOS/TempoTheme.swift`
- Add appearance mode preference (`dark`/`light`/`system`, default `dark`) with toggle in Preferences UI
- Wire `preferredColorScheme` override through app entry points
- Populate empty `AccentColor.colorset` files across all 4 targets with terracotta `#C96442`
- Adopt calmer Claude Code status colors (e.g., error `#D47563` replaces `#EF5363`)
- Introduce `highlight` token (`#9B87F5`) for 7d ring and emphasis elements

## Capabilities

### New Capabilities
- `claude-code-palette`: Unified color theme system with dark/light mode support and adaptive token resolution across all platforms

### Modified Capabilities
- `tempo-theme`: **BREAKING** — Replaced entirely by `claude-code-palette`. All `TempoTheme.*` references become `ClaudeCodeTheme.*`
- `claude-theme`: **BREAKING** — Replaced entirely by `claude-code-palette`. All `Color.claude*` references become `ClaudeCodeTheme.*`
- `macos-settings-preferences`: New appearance mode toggle (dark/light/system) added to preferences panel
- `popover-ring-dashboard`: Ring colors updated to new palette tokens; 7d ring uses `highlight` instead of `info`

## Impact

- **All SwiftUI views across macOS, watchOS, iOS**: Color token references change from `TempoTheme.*` / `Color.claude*` to `ClaudeCodeTheme.*`
- **Xcode asset catalogs**: 4 `AccentColor.colorset` files populated with `#C96442`
- **MacSettingsStore**: New `appearanceMode` UserDefaults key
- **App coordinators / entry points**: `preferredColorScheme` environment override wired based on preference
- **No API or data model changes** — purely visual
