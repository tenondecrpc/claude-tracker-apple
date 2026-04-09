## 1. iCloud Data Pipeline

- [x] 1.1 Extend iOS iCloud reader to track both `usage.json` and `usage-history.json` via `NSMetadataQuery` and coordinated reads
- [x] 1.2 Add decode and normalization path for history snapshots consumed by iOS activity views
- [x] 1.3 Implement per-file freshness tracking (usage/history) plus combined sync state (`waiting`, `syncing`, `stale`)
- [x] 1.4 Keep WatchConnectivity relay wired to fresh iCloud `UsageState` updates while preserving existing payload contract

## 2. Shared Model Preparation

- [x] 2.1 Add/adjust shared DTOs and pure transformation helpers in `Shared/` for dashboard and history summary derivations
- [x] 2.2 Add unit-testable logic for staleness calculations and chart window/range filtering (without UI dependencies)
- [x] 2.3 Ensure new shared types are available across targets without moving UI, iCloud, or WCSession code into `Shared/`

## 3. iOS App Structure Parity

- [x] 3.1 Replace the single-state iOS root screen with a tab-based shell (`Dashboard`, `Activity`, `Settings`)
- [x] 3.2 Introduce an iOS app-level observable store/coordinator that feeds all tabs from the unified iCloud read state
- [x] 3.3 Preserve lifecycle behavior so metadata query and relay activation recover correctly on foreground transitions

## 4. Dashboard UI Parity

- [x] 4.1 Build iOS dashboard cards for 5-hour and 7-day usage, reset timing, and burn-rate summary from iCloud data
- [x] 4.2 Add promo and extra-usage sections that appear conditionally based on `UsageState` flags
- [x] 4.3 Implement explicit waiting/stale/error states with last-updated messaging and clear recovery guidance
- [x] 4.4 Apply `ClaudeCodeTheme` tokens to all dashboard surfaces, accents, and status semantics

## 5. Activity and Settings UI Parity

- [x] 5.1 Implement iOS activity screen rendering from `usage-history.json` with range controls and per-series visibility toggles
- [x] 5.2 Add empty-state and stale-history states that do not block fresh dashboard usage
- [x] 5.3 Implement iOS settings screen with parity-relevant controls (display preferences) and iCloud sync diagnostics
- [x] 5.4 Persist iOS-local settings choices (for example time format and chart display controls)
- [x] 5.5 Apply `ClaudeCodeTheme` tokens across activity/settings cards, typography, and chart styling

## 6. iCloud History Sync Compatibility

- [x] 6.1 Verify macOS history mirror output remains deterministic (deduped, sorted, pruned) for iOS consumption
- [x] 6.2 Ensure iCloud history write/read paths and schema compatibility remain stable across macOS and iOS targets
- [x] 6.3 Confirm iCloud outage behavior degrades gracefully: local history continues on macOS and iOS surfaces stale indicators

## 7. Cleanup and Verification

- [x] 7.1 Remove or isolate legacy iOS OAuth-dependent UI/data paths so iCloud is the sole data source for iOS usage surfaces
- [x] 7.2 Validate iPhone layouts (compact and regular width), Dynamic Type readability, and visual parity with Claude palette
- [x] 7.3 Run manual end-to-end checks: macOS poll/write -> iCloud update -> iOS dashboard/activity/settings refresh -> watch relay transfer
- [x] 7.4 Update documentation notes for iOS parity behavior and iCloud data expectations
