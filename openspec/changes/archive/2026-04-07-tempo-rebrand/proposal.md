## Why

The macOS app "Usage for Claude" shares a near-identical UI pattern with two competing apps (claude-usage-bar and CUStats), making it indistinguishable at a glance. A full visual and structural rebranding is needed to establish a distinct product identity, improve information hierarchy, and deliver a more polished experience - without losing any existing functionality.

## What Changes

- **New display name**: "Tempo for Claude" (windows) / "Tempo" (popover header); project stays `tempo-for-claude` internally
- **New color system**: Graphite + Electric Violet palette (`TempoTheme`) replacing the current Navy + Terracotta (`ClaudeTheme`)
- **Popover redesigned**: Concentric ring gauges replace flat linear progress bars; Extra Usage moves into a collapsed disclosure inside the burn rate card
- **Stats detail window restructured**: Single scrolling column replaced by a horizontal tab bar (Overview / Activity / Insights / Preferences) with a card grid layout on Overview
- **Settings relocated**: Moved from a gear-icon floating popover to a dedicated Preferences tab inside the stats window
- **Menu bar icon replaced**: Signal-strength bars replaced by a "pulse dot" - a circle with an arc ring whose sweep angle represents session utilization
- **Extra Usage restructured**: No longer a third identical bar block; becomes a disclosure group in the popover and a dedicated card in the detail window
- **Desirable features documented**: CUStats capabilities not in scope are captured in `docs/DESIRABLE_FEATURES.md` for future work

## Capabilities

### New Capabilities

- `tempo-theme`: New color token system (TempoTheme) - warm graphite backgrounds, electric violet accent, teal-green/rose/amber status colors
- `popover-ring-dashboard`: Concentric ring gauge dashboard replacing the flat VStack popover layout, with pill chips and burn rate card
- `detail-window-tab-navigation`: Horizontal top tab bar (Overview / Activity / Insights / Preferences) replacing single-column scroll in the stats detail window
- `preferences-tab`: Settings relocated from floating gear popover into the Preferences tab of the detail window, organized in grouped card sections
- `pulse-dot-icon`: New menu bar icon - circular dot with arc ring sweep encoding session utilization, replacing the 3-bar signal-strength icon

### Modified Capabilities

- `macos-menu-bar-ui`: Popover width changes (310 → 320pt), ring gauge layout replaces VStack+progress bars, Extra Usage moves to disclosure group, header branding updates to "Tempo"
- `extra-usage`: Display location changes - moves from primary inline bar in popover to collapsed disclosure inside burn rate card (popover) and standalone card (detail window Overview tab)
- `macos-settings-preferences`: Settings UI moves from floating popover to dedicated Preferences tab; same 5 toggles, but grouped into card sections (General / Data & Sync / Account)
- `claude-theme`: All color tokens replaced with TempoTheme equivalents; file renamed from `ClaudeTheme.swift` to `TempoTheme.swift`
- `welcome-window`: Branding text updated to "Tempo for Claude"; mock popover preview replaced with ring gauge preview; all ClaudeTheme refs updated

## Impact

- **Modified files (macOS target)**: `ClaudeTheme.swift` → `TempoTheme.swift`, `AuthenticatedView.swift` → `DashboardPopoverView.swift`, `MenuBarComponents.swift` → `PopoverComponents.swift`, `StatsDetailView.swift` → `DetailWindowView.swift`, `DynamicMenuBarIconView.swift` → `MenuBarIconView.swift`, `WelcomeWindow.swift`, `SignInView.swift`, `TempoMacApp.swift`
- **New file**: `docs/DESIRABLE_FEATURES.md`
- **No API changes**: All data sources, polling logic, OAuth, iCloud sync, and calculations are preserved
- **No model changes**: `UsageState`, `ExtraUsage`, `UsageHistory`, `SessionInfo` remain unchanged
- **No watch/iOS impact**: `Shared/Theme.swift` palette updated to match Tempo but structure unchanged
- **Breaking**: All internal `ClaudeTheme.*` references must be replaced with `TempoTheme.*`
