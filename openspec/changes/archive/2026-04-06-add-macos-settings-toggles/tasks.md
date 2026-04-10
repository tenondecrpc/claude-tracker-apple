## 1. Settings Domain and UI Surface

- [x] 1.1 Create `MacSettingsStore` with persisted keys for launch-at-login, show-percentage, 24-hour time, service-status monitoring, and iCloud history sync.
- [x] 1.2 Inject settings store through `MacAppCoordinator` and wire consumers (menu popover, stats view, icon view, history service).
- [x] 1.3 Add settings entry point in stats/history UI (gear/settings control) and render toggles with current values.
- [x] 1.4 Persist toggle changes immediately and restore values on app relaunch.

## 2. Launch at Login Integration

- [x] 2.1 Implement launch-at-login manager using `SMAppService.mainApp` register/unregister.
- [x] 2.2 Add install-location support check and helper messaging for unsupported app locations.
- [x] 2.3 Bind Launch at Login toggle to manager state and failure handling.

## 3. Menu Bar Presentation Preferences

- [x] 3.1 Update `DynamicMenuBarIconView` to honor Show Percentage preference (text shown/hidden while icon behavior remains intact).
- [x] 3.2 Introduce shared time-format policy utility used by popover reset labels (24h vs 12h).
- [x] 3.3 Replace hard-coded reset/weekly formatter usage in authenticated popover with preference-driven formatting.
- [x] 3.4 Show a `2x promo active` indicator above `Current Session`, aligned to the right, when double-limit promotion detection is active.
- [x] 3.5 Align OpenSpec artifacts (proposal/design/specs) with implemented `2x promo active` behavior.

## 4. Service Status Monitoring

- [x] 4.1 Implement `ServiceStatusMonitor` with periodic polling and decode of status endpoint response.
- [x] 4.2 Map endpoint indicators to internal states (`operational`, `degraded`, `majorOutage`, `stale`, `unavailable`) with tolerant parsing.
- [x] 4.3 Start/stop monitor based on Service Status Monitoring toggle and keep it isolated from `UsagePoller`.
- [x] 4.4 Expose health state in menu bar experience (indicator/status row) and ensure unavailable/stale fallbacks are non-blocking.

## 5. iCloud History Sync

- [x] 5.1 Extend `UsageHistory` with optional iCloud mirror path (`Documents/Tempo/usage-history.json`) controlled by sync toggle.
- [x] 5.2 Implement merge-and-dedupe between local and iCloud histories (union, sort, prune by retention).
- [x] 5.3 Trigger sync on launch and after local append/save, with graceful retry behavior on iCloud failures.
- [x] 5.4 Ensure disabling sync stops mirror writes without deleting local history.

## 6. Validation and Regression Checks

- [x] 6.1 Manually verify toggle persistence and behavior across relaunch for all five settings.
- [x] 6.2 Manually verify launch-at-login behavior on supported and unsupported install locations.
- [x] 6.3 Manually verify service-status states (operational, degraded/outage, unavailable) do not affect usage polling.
- [x] 6.4 Manually verify iCloud history convergence across two Macs and no local-data loss during temporary iCloud outages.
