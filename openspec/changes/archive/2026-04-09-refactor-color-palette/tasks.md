## 1. Create Unified Theme

- [x] 1.1 Create `Shared/ClaudeCodeTheme.swift` with `AppearanceMode` enum (`.dark`, `.light`, `.system`) and all 19 dark mode tokens
- [x] 1.2 Add all 19 light mode token variants with conditional resolution via `#if os(macOS)` reading `MacSettingsStore.shared.appearanceMode`
- [x] 1.3 On watchOS/iOS, hardcode dark mode resolution (no MacSettingsStore dependency)

## 2. Appearance Mode Preference

- [x] 2.1 Add `appearanceMode` property to `MacSettingsStore` with UserDefaults persistence, default `.dark`
- [x] 2.2 Add segmented Picker (Dark / Light / System) to `PreferencesWindowView` in an "Appearance" row
- [x] 2.3 Wire `preferredColorScheme` environment override in app entry point / coordinator based on `appearanceMode`

## 3. Migrate macOS References (TempoTheme → ClaudeCodeTheme)

- [x] 3.1 Replace `TempoTheme.` → `ClaudeCodeTheme.` in `DashboardPopoverView.swift`
- [x] 3.2 Replace `TempoTheme.` → `ClaudeCodeTheme.` in `DetailWindowView.swift`
- [x] 3.3 Replace `TempoTheme.` → `ClaudeCodeTheme.` in `PreferencesWindowView.swift`
- [x] 3.4 Replace `TempoTheme.` → `ClaudeCodeTheme.` in `PopoverComponents.swift`
- [x] 3.5 Replace `TempoTheme.` → `ClaudeCodeTheme.` in `WelcomeWindow.swift`
- [x] 3.6 Replace `TempoTheme.` → `ClaudeCodeTheme.` in `SignInView.swift`
- [x] 3.7 Replace `TempoTheme.critical` → `ClaudeCodeTheme.error` across all macOS files
- [x] 3.8 Replace remaining `TempoTheme.` references in any other macOS Swift files

## 4. Migrate watchOS References (Color.claude* → ClaudeCodeTheme)

- [x] 4.1 Replace `Color.claudeAccent` → `ClaudeCodeTheme.accent` in `ContentView.swift`
- [x] 4.2 Replace `Color.claudeGreen/Yellow/Red` → `ClaudeCodeTheme.success/warning/error` in `ringColor()` function
- [x] 4.3 Replace `Color.claudeBlue` → `ClaudeCodeTheme.highlight` for 7d ring
- [x] 4.4 Replace `Color.claudeRingTrack/RingTrackInner` → `ClaudeCodeTheme.ringTrack/ringTrackInner`

## 5. Populate AccentColor Asset Catalogs

- [x] 5.1 Update `Tempo/Assets.xcassets/AccentColor.colorset/Contents.json` with #C96442
- [x] 5.2 Update `Tempo Watch/Assets.xcassets/AccentColor.colorset/Contents.json` with #C96442
- [x] 5.3 Update `Tempo Watch Extension/Assets.xcassets/AccentColor.colorset/Contents.json` with #C96442
- [x] 5.4 Update `Tempo macOS/Assets.xcassets/AccentColor.colorset/Contents.json` with #C96442

## 6. Cleanup

- [x] 6.1 Delete `Shared/Theme.swift`
- [x] 6.2 Delete `Tempo macOS/TempoTheme.swift`
- [x] 6.3 Verify no remaining references to `TempoTheme`, `Color.claude`, or `Theme.swift` compile

## 7. Verification

- [x] 7.1 Build macOS target — zero compile errors
- [x] 7.2 Build watchOS target — zero compile errors
- [x] 7.3 Build iOS target — zero compile errors
