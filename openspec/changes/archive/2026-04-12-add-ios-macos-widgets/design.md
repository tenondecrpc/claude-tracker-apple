## Context

Tempo already has the core data pipeline needed for glanceable usage surfaces:
- macOS polls the Anthropic usage endpoint and writes `usage.json` to iCloud.
- iOS reads `usage.json` from iCloud, renders the dashboard, and relays data to watchOS.
- watchOS already uses a WidgetKit complication fed by app-written App Group data and `WidgetCenter.shared.reloadAllTimelines()`.

The requested widget references map well to Tempo's current product language: a ring-focused square widget, a wider bar-summary widget, and a compact stacked-metrics widget. The main architectural constraint is repository structure: `Shared/` is reserved for models and pure logic, and widget views must not be moved there. The project also has separate iOS and macOS targets rather than a single multiplatform app target.

## Goals / Non-Goals

**Goals:**
- Add glanceable WidgetKit widgets for iOS and macOS without introducing any direct network or iCloud reads from widget extensions.
- Reuse existing `UsageState` metrics and ClaudeCode theme semantics across widget layouts.
- Keep widget refreshes app-driven, using the same pattern already proven by the watch complication.
- Share only pure widget data models, formatting helpers, and storage helpers in `Shared/`.
- Provide clear waiting, stale, and mock states so widgets remain understandable when source data is missing or old.
- Open Tempo when a widget is tapped, landing in the most relevant dashboard surface per platform.

**Non-Goals:**
- Lock Screen or accessory widgets for iPhone/iPad.
- Interactive widgets, controls, or configuration intents in v1.
- Direct widget reads from `NSMetadataQuery`, OAuth APIs, or iCloud Drive documents.
- Adding new usage metrics beyond what already exists in `UsageState`.
- Reworking the existing watch complication or watch data flow.

## Decisions

### 1. Use two widget extension targets with a shared snapshot contract

**Choice:** Add one iOS widget extension target and one macOS widget extension target. Share only a pure snapshot model, cache helpers, routes, and formatting utilities through `Shared/`.

**Why:** This matches the repository rule that views do not belong in `Shared/`, while still avoiding duplicate business logic. Each extension can keep its own SwiftUI widget view files and target-specific configuration, but both render the same underlying widget snapshot contract.

**Alternative considered:** A single cross-platform widget implementation with shared widget views. Rejected because the project is already split by platform and `Shared/` is not the place for view code.

### 2. Persist a single versioned widget snapshot in App Group storage

**Choice:** Define a `WidgetUsageSnapshot` model in `Shared/` and store it as one JSON payload in a platform-specific App Group container used by the host app and its widget extension.

**Why over multiple `UserDefaults` keys:** The widget needs several related fields at once: session percentage, weekly percentage, reset labels or timestamps, extra-usage values, promo/mock flags, and freshness metadata. A single snapshot is easier to version, read atomically, and evolve without key drift.

**Alternative considered:** Per-field App Group `UserDefaults` keys. Rejected because it creates schema sprawl and makes partial updates more error-prone.

### 3. Keep widget timelines static and reload from the host app

**Choice:** Widget providers return a single entry with `.never` reload policy. The iOS app and macOS app write the snapshot and then explicitly trigger `WidgetCenter` reloads.

**Why:** Tempo data is already event-driven by iCloud updates on iOS and API polls on macOS. App-triggered reloads keep widgets aligned with the real source-of-truth update moments and mirror the existing watch complication pattern.

**Alternative considered:** Scheduled widget timelines. Rejected because WidgetKit scheduling would be less aligned with Tempo's existing data pipeline and could refresh either too late or unnecessarily often.

### 4. Limit v1 layouts to three deliberate variants

**Choice:** Ship three non-configurable widget variants inspired by the provided screenshots:
- Ring widget: small square layout with a large session percentage ring and secondary weekly context.
- Summary widget: medium rectangular layout with horizontal bars for session and weekly usage, plus reset labels.
- Compact metrics widget: small square layout with stacked numeric metrics for session and weekly usage when text density is preferred over the ring.

**Why:** These three variants cover the strongest use cases from the references without multiplying implementation scope across every family and option combination.

**Alternative considered:** Support every WidgetKit family immediately, including lock screen and accessory families. Rejected because the first release should focus on the desktop/home-screen experience the user asked for.

### 5. Derive widget content from `UsageState` plus freshness metadata only

**Choice:** Build the widget snapshot from `UsageState`, host-app update timestamps, and a small amount of presentation metadata (`isMocked`, promo flag, extra usage).

**Why:** The requested widget designs focus on current session, weekly, resets, and extra usage. They do not require history arrays, chart points, or session-event detail. Using only `UsageState` keeps the implementation small and robust.

**Alternative considered:** Include recent history or latest session records in the widget snapshot. Rejected because that increases payload complexity without supporting the requested layouts.

### 6. Add explicit widget routes for taps

**Choice:** Introduce lightweight app routes that widgets can open, such as a dashboard route on iOS and the stats/detail window on macOS.

**Why:** Widget taps should land the user in a relevant Tempo surface instead of merely opening the app shell. This is especially important on macOS where the app has multiple windows and a menu bar flow.

**Alternative considered:** Rely on default app launch only. Rejected because it gives inconsistent results and misses a straightforward navigation improvement.

## Risks / Trade-offs

- [Widget refresh budget limits] -> Use app-triggered `.never` timelines and reload only after real data changes.
- [Cross-platform drift between iOS and macOS widget visuals] -> Share one snapshot contract and one set of metric/threshold rules, while keeping only the view layer per target.
- [Stale snapshots surviving temporary failures] -> Preserve the last valid snapshot and expose freshness in the widget UI instead of clearing content on transient errors.
- [App Group provisioning complexity] -> Use separate, explicit App Group capabilities for iOS and macOS widget pairs and validate both in Xcode target settings.
- [Shared-folder misuse] -> Keep `Shared/` limited to models, storage helpers, deep-link routes, and formatting logic; widget SwiftUI view code stays inside each widget target.

## Migration Plan

1. Add `WidgetUsageSnapshot`, cache helpers, freshness utilities, and widget routes in `Shared/`.
2. Update iOS iCloud sync flow to materialize the snapshot into its App Group and reload iOS widget timelines when usage changes.
3. Update macOS polling flow to materialize the snapshot into its App Group and reload macOS widget timelines after successful polls.
4. Add iOS and macOS widget extension targets with the three widget variants and placeholder/empty-state rendering.
5. Add widget deep-link handling in both apps.
6. Manually verify:
   - iOS widget updates after new iCloud `usage.json`
   - macOS widget updates after successful poll
   - stale/empty/mock states render correctly
   - widget taps open the expected destination

Rollback strategy:
- Remove widget targets and stop writing the widget snapshot, leaving the existing iCloud, macOS, and watch flows unchanged.

## Open Questions

- Should the widget display an explicit "From iPhone" or "From This Mac" source label on macOS, or is the metric-only presentation sufficient for v1?
- Should the compact small widget prioritize weekly reset text or extra-usage text when there is not enough vertical space for both?
- Do we want the first version to expose one shared widget display name ("Tempo Usage") or platform-specific names for the ring and compact variants?
