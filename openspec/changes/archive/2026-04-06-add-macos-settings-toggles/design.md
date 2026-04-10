## Context

The macOS app already renders usage in a menu bar popover, supports a stats/history window, persists local snapshots to `~/.config/tempo-for-claude/usage-history.json`, and writes current `UsageState` to iCloud for iOS/watch relay. However, it does not yet expose the full set of user-configurable controls shown in the requested settings UI:
- Launch at Login
- Show Percentage in Menu Bar
- 24-Hour Time
- Service Status Monitoring
- Sync History via iCloud

Current behavior is mostly hard-coded (menu bar percentage always visible, 24-hour time always used, no service health feed, no cross-Mac history sync). This change introduces a unified settings domain and wires these preferences into existing menu bar, history, and polling systems.
Additionally, the authenticated menu view should surface a small `2x promo active` indicator when the usage payload reports an active double-limit promotion.

Note on reference implementation review: `claude-usage-bar` includes launch-at-login management patterns (`SMAppService`) but does not currently implement a Claude service-status monitoring feature, so service monitoring here should be treated as a new implementation.

## Goals / Non-Goals

**Goals:**
- Add a persistent settings surface for the enabled features in the screenshot.
- Ensure each preference has immediate behavioral impact where applicable.
- Keep existing OAuth, polling, and watch relay contracts intact.
- Add resilient service-status monitoring that never blocks core usage polling.
- Add optional iCloud sync for historical snapshot data across Macs.
- Surface active double-limit promotion state (`2x promo active`) in the authenticated menu view.

**Non-Goals:**
- Implementing the disabled "Show Clock on Progress" toggle in this change.
- Replacing existing usage API polling cadence/backoff strategy.
- Adding server-side storage or backend schema changes.
- Changing watchOS/iOS UI behavior beyond existing `usage.json` relay flow.

## Decisions

### 1. Centralize preferences in a dedicated macOS settings model
Create an observable `MacSettingsStore` backed by `UserDefaults` with explicit keys for each toggle. UI controls bind to this store, and consuming features subscribe to changes.

Alternative considered:
- Ad-hoc `@AppStorage` sprinkled across views. Rejected because cross-feature coordination (service monitor start/stop, history sync enable/disable, formatter policy) becomes fragmented and harder to test.

### 2. Place settings entry in stats/chart context with gear popover
Expose settings from the history/stats experience (gear near chart controls) so users can adjust viewing and sync behavior where they inspect data. Keep popover actions focused on quick app actions.

Alternative considered:
- Put all toggles directly into the menu bar popover action list. Rejected because it increases menu clutter and is less aligned with the requested reference interaction.

### 3. Use `SMAppService.mainApp` for launch-at-login management
Implement launch-at-login through `ServiceManagement`, with capability detection based on app install location and clear disabled-state messaging when unsupported.

Alternative considered:
- Legacy Login Items APIs. Rejected due to deprecation and lower reliability on modern macOS.

### 4. Introduce a lightweight service-status monitor isolated from usage polling
Create a dedicated `ServiceStatusMonitor` (timer + async fetch) that polls Anthropic's status endpoint (default `https://status.anthropic.com/api/v2/status.json`) and maps response indicators to app-level states (`operational`, `degraded`, `majorOutage`, `unavailable`, `stale`).

Alternative considered:
- Fold status checks into `UsagePoller`. Rejected because failures/noise from status polling would couple with core usage retrieval and complicate retry behavior.

### 5. Sync history via iCloud using mirrored JSON with deterministic merge
Extend `UsageHistory` with an optional iCloud mirror file (`Documents/Tempo/usage-history.json`) when sync is enabled. On launch and write events, merge local + cloud snapshots by deterministic identity (`date + utilization5h + utilization7d` normalization), dedupe, sort by date, prune to retention window, then write back.

Alternative considered:
- Last-writer-wins whole-file replacement. Rejected because concurrent multi-Mac updates can lose snapshots.

### 6. Time formatting controlled by one formatter policy
Route reset/relative timestamp formatting through a shared formatter policy (`24h` vs `12h`) consumed by menu and stats contexts, instead of hard-coded date formats in views.

Alternative considered:
- Local formatter conditionals in each view. Rejected due to duplication and risk of inconsistent output.

### 7. Use tolerant promo detection with deterministic UI fallback
Parse usage response payloads with tolerant key matching for known and inferred promo fields (`iguana_necktie`, explicit promo flags, multiplier signals). Only show the promo indicator when an active state can be positively inferred.

Alternative considered:
- Treat presence of any promo-related field as active. Rejected due to false-positive risk when fields are present but null/disabled.

## Risks / Trade-offs

- [Status endpoint contract changes] -> Keep decoder tolerant and map unknown values to `unavailable` with safe fallback UI.
- [iCloud file race conditions across Macs] -> Merge both sides before write and dedupe by deterministic snapshot identity.
- [Launch-at-login confusion when app location is unsupported] -> Disable toggle with explanatory helper text.
- [Preference proliferation in view code] -> Use a single settings store injected via coordinator/environment.
- [Extra network work for status monitor] -> Use modest polling interval and suspend timer when monitoring is off.

## Migration Plan

1. Add `MacSettingsStore` with defaults aligned to current behavior where possible (`showPercentage = true`, `use24HourTime = true`, `serviceStatusMonitoring = true`, `syncHistoryViaICloud = true`; launch-at-login reflects system state).
2. Add settings UI and wiring, then apply preference-driven behavior in menu icon and time formatting.
3. Add `ServiceStatusMonitor` and render status indicators behind the feature toggle.
4. Add `UsageHistory` iCloud mirror + merge logic behind sync toggle.
5. Validate manually:
   - Toggle persistence across relaunch
   - Launch-at-login on/off on installed app
   - Percentage visible/hidden in menu bar
   - 12h vs 24h time format updates
   - Service status operational/degraded/unavailable states
   - Multi-Mac iCloud history convergence

Rollback strategy:
- Disable new toggles and fall back to existing local-only behavior by bypassing settings-driven branches.

## Open Questions

- Should service status be represented only as an icon indicator or also as textual status in the popover/settings row?
- Should iCloud history sync be enabled by default for first-time users, or should onboarding ask for explicit opt-in?
- Should status polling run while signed out, or only when authenticated?
