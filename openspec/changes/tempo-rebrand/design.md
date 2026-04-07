## Context

The macOS app currently uses a flat VStack popover layout and a single-column scrolling stats window — patterns shared by both direct competitors. All views use `ClaudeTheme` (navy + terracotta), enforced dark mode only, and a signal-strength menu bar icon. The rebranding replaces visual and structural patterns across every user-facing surface while preserving all existing data models, services, and business logic entirely.

## Goals / Non-Goals

**Goals:**
- Replace all `ClaudeTheme` tokens with `TempoTheme` (graphite + electric violet)
- Replace linear progress bars with concentric ring gauges in the popover
- Replace the single-column scroll in `StatsDetailView` with a top tab bar + card grid
- Move settings from a gear-icon popover into a dedicated Preferences tab
- Move Extra Usage from an inline bar block into a disclosure group (popover) and card (detail window)
- Replace the 3-bar menu bar icon with a "pulse dot" arc ring icon
- Update all branding text to "Tempo for Claude" / "Tempo"
- Create `docs/DESIRABLE_FEATURES.md` listing out-of-scope CUStats features

**Non-Goals:**
- Multi-account support
- Light mode
- Any changes to data models (`UsageState`, `ExtraUsage`, `UsageHistory`, `SessionInfo`)
- Any changes to polling, OAuth, iCloud sync, or API logic
- iOS or watchOS UI changes (only `Shared/Theme.swift` palette sync)
- New data visualizations beyond what already exists in `StatsDetailView`

## Decisions

### D1: Replace ClaudeTheme with TempoTheme (new file, not in-place edit)

**Decision**: Create `TempoTheme.swift` as a new file and delete `ClaudeTheme.swift`.

**Rationale**: A clean break ensures no stale references survive. Renaming in-place risks Xcode caching the old type. Creating a new file and removing the old one forces a clean compile-time audit of every reference.

**Alternative considered**: Rename `ClaudeTheme` → `TempoTheme` via Xcode refactor. Rejected: doesn't change the file on disk cleanly for reviewers; git history reads more clearly with a delete + add.

---

### D2: Concentric rings via ZStack + Circle().trim (no third-party dependency)

**Decision**: Implement ring gauges using `ZStack` of `Circle().trim(from:to:).stroke()` shapes, rendered via SwiftUI natively.

**Rationale**: The `.trim` modifier on `Circle` combined with `.stroke(style: StrokeStyle(lineWidth:, lineCap: .round))` and `.rotationEffect(.degrees(-90))` produces clean anti-aliased arcs. This is the standard SwiftUI pattern for circular progress indicators and requires no external library.

**Alternative considered**: `CircularProgressViewStyle` with `ProgressView`. Rejected: not customizable enough for two concentric rings with distinct sizes and colors.

**Implementation note**: The outer ring (weekly, `TempoTheme.info` sky blue, lineWidth 8) is drawn first; then the inner ring (session, `TempoTheme.accent` violet, lineWidth 10) uses `.padding(18)` to create the concentric gap. The track circles are drawn at full opacity using `TempoTheme.progressTrack` behind each fill ring.

---

### D3: Top tab bar using custom buttons, not TabView or SwiftUI `tabItem`

**Decision**: Implement the detail window tab bar as a custom `HStack` of `Button` views with `@State private var selectedTab: DetailTab`.

**Rationale**: macOS `TabView` renders with native `NSTabView` chrome (visible divider, system-styled tabs) that conflicts with the card-based design aesthetic. The custom approach gives full control over active state styling (accent background pill, colored text) and animation.

**Alternative considered**: `TabView` with `tabItem`. Rejected: native chrome clashes with card UI; `.tabViewStyle(.automatic)` on macOS creates a visible tab bar divider that can't be removed.

**Implementation note**: `DetailTab` is a `String, CaseIterable` enum with cases `.overview`, `.activity`, `.insights`, `.preferences`. The tab bar is an `HStack` in the window header, below the title row. Tab content is a `Group { switch selectedTab { ... } }` in a `VStack` below.

---

### D4: Settings in Preferences tab, not a separate window

**Decision**: Embed settings in the fourth tab of the detail window rather than a separate `Settings` scene or a floating popover.

**Rationale**: macOS convention for a separate `Settings` window (`Settings { ... }` scene) conflicts with the in-window tab paradigm we're establishing. Moving settings inline eliminates the gear icon (simplifying the header), creates a predictable discovery path (users explore tabs naturally), and lets us style the settings surface with the same card layout as the rest of the window.

**Alternative considered**: macOS `Settings` scene with `Form { }.formStyle(.grouped)`. Rejected: this is exactly what Competitor 1 (claude-usage-bar) uses — directly copying it would undermine differentiation.

---

### D5: Extra Usage as DisclosureGroup in popover, dedicated card in detail

**Decision**: In the popover, Extra Usage collapses into a `DisclosureGroup` inside the burn rate card. In the detail window Overview tab, it appears as a standalone card in the 2-column grid.

**Rationale**: In the popover, when Extra Usage is disabled (the common case), showing it as a collapsed disclosure avoids clutter. When enabled, expanding it reveals the dollar amounts without permanently consuming vertical space. In the detail window, a dedicated card is appropriate since there's more space and richer context (monthly spend, days left) can be shown.

**Alternative considered**: Always show Extra Usage as a third ring in the popover. Rejected: a third ring would overcrowd the ring area and reduce the visual clarity of the session/weekly duality.

---

### D6: Pulse dot icon drawn with CGContext, isTemplate = true

**Decision**: The new menu bar icon is drawn programmatically using `CGContext` in an `NSImage` drawing block, then marked `isTemplate = true`.

**Rationale**: Template images automatically adapt to system tint and light/dark menu bar variants, consistent with macOS icon guidelines. CGContext gives pixel-level control over the arc geometry without requiring an asset catalog. The icon must be exactly 18×18pt at 2x retina.

**Drawing geometry**:
- Canvas: 18×18pt
- Track circle: center (9,9), radius 6pt, `lineWidth 1.5`, opacity 30%
- Arc fill: same center/radius, start angle −90°, end angle = `utilization * 360° − 90°`, `lineWidth 1.5`, `lineCap .round`
- Center dot: filled ellipse, 5×5pt centered at (6.5, 6.5)

---

### D7: Card grid using LazyVGrid with two fixed columns

**Decision**: The Overview tab card grid uses `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16)`.

**Rationale**: Two equal-width flexible columns fill the available width automatically and adapt if the window is resized. `LazyVGrid` with `.flexible()` columns is the standard SwiftUI pattern for responsive card grids.

**Card structure**: Each card is a `VStack(alignment: .leading, spacing: 10)` padded 16pt, with `TempoTheme.card` background, 12pt corner radius, and a 4pt left-edge accent stripe in the card's accent color.

## Risks / Trade-offs

- **File rename risk**: Xcode's PBX file system synchronized root (`PBXFileSystemSynchronizedRootGroup`) should automatically pick up renamed files, but if the old file name is cached in build intermediates, a clean build may be needed. Mitigation: delete derived data after renaming files.

- **ClaudeTheme reference completeness**: Any missed `ClaudeTheme` reference will produce a compile error (the type will no longer exist). This is actually desirable — the compiler enforces the migration. Mitigation: grep for `ClaudeTheme` before marking implementation complete.

- **Ring gauge animation**: The `Circle().trim` approach does not natively animate the ring on value changes without explicit `withAnimation`. Since the popover updates via `TimelineView(.periodic(from:by: 30))`, no smooth animation is needed — values update discretely. Non-issue for this scope.

- **DisclosureGroup styling**: `DisclosureGroup` on macOS uses system chevron styling which may not perfectly match the card aesthetic. Mitigation: Use `.disclosureGroupStyle` or wrap in a custom disclosure button if the system style clashes too much. Mark as an acceptable cosmetic trade-off for initial implementation.

- **Preferences tab settings discovery**: Users previously accessed settings via the gear icon in the stats header. The gear icon is removed. Users unfamiliar with tabs may not find settings immediately. Mitigation: The "Preferences" tab label is explicit and follows standard app conventions.

## Open Questions

None — all design decisions resolved. Implementation may proceed directly to specs and tasks.
