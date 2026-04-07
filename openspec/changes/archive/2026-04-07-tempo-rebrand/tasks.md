## 1. Foundation: TempoTheme + Desirable Features Doc

- [x] 1.1 Create `ClaudeTracker macOS/TempoTheme.swift` with all design tokens: background, surface, card, accent, accentLight, accentMuted, textPrimary, textSecondary, textTertiary, progressTrack, success, warning, critical, info, destructive
- [x] 1.2 Create `docs/DESIRABLE_FEATURES.md` documenting 10 CUStats features out of scope for this rebranding (multi-account, light mode, pace prediction, live session chart, day/week breakdowns, bar charts, consumption rate histogram, scheduled triggers, Codex support, All Accounts dashboard)
- [x] 1.3 Delete `ClaudeTracker macOS/ClaudeTheme.swift` after TempoTheme is in place

## 2. Popover Components (PopoverComponents.swift)

- [x] 2.1 Rename `MenuBarComponents.swift` to `PopoverComponents.swift`; update `UsageProgressBar` to use `TempoTheme.progressTrack` and `TempoTheme.accent`
- [x] 2.2 Build `UsageRingView` component: concentric `Circle().trim` rings, outer (weekly, `TempoTheme.info`, lineWidth 8pt), inner (session, `TempoTheme.accent`, lineWidth 10pt, padding 18pt), both with track rings in `TempoTheme.progressTrack`, center label in `.system(size:28, weight:.bold, design:.rounded)`
- [x] 2.3 Build session and weekly pill chip components: `TempoTheme.surface` background, 8pt corner radius, left-edge 3pt accent stripe, `.callout.monospacedDigit()` values, `.footnote` labels
- [x] 2.4 Build `BurnRateCard` component: `TempoTheme.card` background, 12pt corner radius, colored status dot, "On track/High burn · X%/hr" label, reset countdown in `.footnote`, `DisclosureGroup` at bottom for Extra Usage (collapsed by default, shows `$X.XX/$Y.YY` + thin `TempoTheme.info` progress bar when expanded)
- [x] 2.5 Update `MenuBarHeaderView` to show "Tempo" title, remove help/chat icons, add 8pt service status dot (color per `ServiceHealthState`) left of refresh button

## 3. Popover Dashboard (DashboardPopoverView.swift)

- [x] 3.1 Rename `AuthenticatedView.swift` to `DashboardPopoverView.swift`; update `MacMenuView` reference in `SignInView.swift`
- [x] 3.2 Set popover width to 320pt in `ClaudeTrackerMacApp.swift` (update `.frame(width:)` on `MenuBarExtra` body)
- [x] 3.3 Replace the flat VStack usage content with the ring dashboard layout: `UsageRingView` (150×150pt, centered), pill chips HStack, `BurnRateCard`, promo indicator (above ring, right-aligned, `TempoTheme.warning`, when `isDoubleLimitPromoActive`)
- [x] 3.4 Move service status row out of the body — it is now only the dot in the header; remove the service status body row from `usageContent`
- [x] 3.5 Update not-signed-in state: replace `ClaudeTheme.lockIcon` with `TempoTheme.info`, replace coral button with `TempoTheme.accent` violet, update subtitle text to "Sign in to view your usage", update quit button to `TempoTheme.critical`
- [x] 3.6 Update action items: remove settings reference (settings now in Preferences tab), keep Usage History + Logout + Quit with `TempoTheme` colors

## 4. Menu Bar Icon (MenuBarIconView.swift)

- [x] 4.1 Rename `DynamicMenuBarIconView.swift` to `MenuBarIconView.swift`
- [x] 4.2 Replace `NSImage.usageBar(percentage:)` with `NSImage.pulseDot(percentage:)`: 18×18pt NSImage, `CGContext` drawing — track circle (center 9,9, radius 6pt, lineWidth 1.5pt, 30% opacity), arc fill (same center/radius, from −90° clockwise by `utilization × 360°`, lineWidth 1.5pt, `lineCap .round`), center filled ellipse (5×5pt at 6.5,6.5), `isTemplate = true`
- [x] 4.3 Verify optional percentage text still renders to the right of the pulse dot when `showPercentage` is enabled

## 5. Stats Detail Window (DetailWindowView.swift)

- [x] 5.1 Rename `StatsDetailView.swift` to `DetailWindowView.swift`; update the `Window("Stats", id: "stats-detail")` scene in `ClaudeTrackerMacApp.swift` to reference `DetailWindowView`
- [x] 5.2 Add `DetailTab` enum with cases `overview`, `activity`, `insights`, `preferences` and `@State private var selectedTab: DetailTab = .overview`
- [x] 5.3 Build custom horizontal tab bar: `HStack` of `Button` views, active tab has `TempoTheme.accentMuted` background pill + `TempoTheme.accent` text + `.semibold` weight, inactive tabs in `TempoTheme.textSecondary` + regular weight, `withAnimation(.easeInOut(duration: 0.2))` on tap
- [x] 5.4 Update window header: title to "Tempo for Claude" in `.title3.weight(.semibold)`, email on the right in `.callout` `TempoTheme.textSecondary`; remove gear icon button entirely (this removes the inline settings popover)
- [x] 5.5 Update window minimum frame to 900×780pt
- [x] 5.6 Replace all `ClaudeTheme.*` references in `DetailWindowView.swift` with `TempoTheme.*`

## 6. Overview Tab

- [x] 6.1 Wrap existing chart section in a card container (`TempoTheme.card` bg, 12pt radius, 16pt padding), make it full-width at top of Overview tab
- [x] 6.2 Build `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16)` below chart card
- [x] 6.3 Build Session card: `UsageRingView` at 64×64pt, session % in `.title3.bold().monospacedDigit()`, reset time in `.footnote`, left-edge 4pt `TempoTheme.accent` stripe
- [x] 6.4 Build Weekly card: same structure as Session card with `TempoTheme.info` stripe
- [x] 6.5 Build Extra Usage card (conditional on `extraUsage?.isEnabled == true`): `$X.XX / $Y.YY` in `.title3.bold().monospacedDigit()`, linear progress bar in `TempoTheme.info`, "Resets monthly" caption, `TempoTheme.info` left stripe
- [x] 6.6 Build Burn Status card: colored status dot, burn assessment text, ETA-to-limit estimate, left stripe color matching status (success/warning)

## 7. Activity Tab

- [x] 7.1 Create Activity tab content: place `ActivityHeatmapView` at top (no changes to heatmap component itself)
- [x] 7.2 Move Claude Code stats aggregate row and project table from their current position in the scroll view to below the heatmap in the Activity tab
- [x] 7.3 Ensure "7 days" accent chip on Claude Code section header uses `TempoTheme.accent` instead of any hardcoded color

## 8. Insights Tab

- [x] 8.1 Move warning card and subscription value card to Insights tab content with 24pt section spacing
- [x] 8.2 Move the four compact stat cards (Avg Session, Avg Weekly, High Usage Days, Peak Session) to Insights tab below the wide cards
- [x] 8.3 Update inline hardcoded colors in insight cards to `TempoTheme` tokens where applicable (red-orange values → `TempoTheme.critical`, blue → `TempoTheme.info`)

## 9. Preferences Tab

- [x] 9.1 Build Preferences tab with three grouped card sections using `TempoTheme.card` bg, 12pt radius, 24pt padding
- [x] 9.2 General card: Launch at Login (icon `power`), Show Percentage in Menu Bar (icon `percent`), 24-Hour Time (icon `clock.arrow.2.circlepath`) — each as HStack with icon, VStack(title+subtitle), and Toggle tinted `TempoTheme.accent`
- [x] 9.3 Data & Sync card: Sync History via iCloud (icon `icloud`), Service Status Monitoring (icon `dot.radiowaves.left.and.right`) — same row structure
- [x] 9.4 Account card: email in `.callout` `TempoTheme.textSecondary`, "Sign Out" button below in `TempoTheme.critical`; wire logout action
- [x] 9.5 Constrain Preferences tab content to max width 560pt, horizontally centered
- [x] 9.6 Remove the old inline settings popover (`@State private var showSettings`, `SettingsPopoverContent` or equivalent) from `DetailWindowView`

## 10. Welcome Window + Sign In

- [x] 10.1 In `WelcomeWindow.swift`: replace "Welcome to Usage for Claude" with "Welcome to Tempo for Claude" in title; replace subtitle with "Track your Claude usage right from your menu bar."
- [x] 10.2 Replace the flat progress bar mock popover preview with a ring gauge preview: hardcoded `UsageRingView` at ~49% session / ~4% weekly, displayed in a `TempoTheme.card` rounded container
- [x] 10.3 Replace all `ClaudeTheme.*` references in `WelcomeWindow.swift` with `TempoTheme.*`
- [x] 10.4 In `SignInView.swift` (`MacMenuView`, `NotSignedInMenuView`): replace all `ClaudeTheme.*` with `TempoTheme.*`, update "Sign In" button to `TempoTheme.accent` violet

## 11. App Entry Point + Polish

- [x] 11.1 In `ClaudeTrackerMacApp.swift`: update `Window("Stats", id: "stats-detail")` title/scene reference; update any "Usage for Claude" strings to "Tempo for Claude"; update `MenuBarExtra` label if it contains branding text
- [x] 11.2 Grep entire macOS target for `ClaudeTheme` — fix any remaining references
- [x] 11.3 Grep entire macOS target for "Usage for Claude" — update remaining occurrences to "Tempo for Claude" or "Tempo" as appropriate
- [x] 11.4 Build the macOS target in Xcode and fix any compile errors
- [x] 11.5 Run the app: verify popover opens with ring gauges, detail window opens with tab bar, Preferences tab shows settings, pulse dot renders in menu bar, welcome flow shows "Tempo for Claude"
