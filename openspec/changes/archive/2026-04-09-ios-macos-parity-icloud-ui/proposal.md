## Why

The iOS app currently acts as a sync-status bridge and does not expose the same usage insights available in the macOS app. Bringing iOS to functional parity now gives users a complete mobile experience while keeping macOS as the single data producer and iCloud as the single source of truth.

## What Changes

- Build a full iOS usage experience that mirrors the macOS app's key capabilities (dashboard, history, and settings-level controls appropriate for iOS).
- Use the Claude color palette consistently across iOS surfaces, cards, charts, and controls to match the app's visual identity.
- Replace any iOS dependency on direct Anthropic/OAuth flows for usage views with iCloud-backed read models only.
- Add clear sync-state UX (fresh/stale/missing data) while preserving WatchConnectivity relay behavior.
- Keep watch handoff working from iOS, but source all payload data from iCloud files written by macOS.

## Capabilities

### New Capabilities
- `ios-usage-dashboard-parity`: iOS home/dashboard UI that mirrors macOS usage metrics, ring visualization, promo indicators, and status messaging using Claude palette tokens.
- `ios-history-and-settings-parity`: iOS history and settings screens that match macOS information architecture where platform-appropriate, including date-range/history presentation and sync/account status details.

### Modified Capabilities
- `icloud-usage-sync`: extend iOS iCloud ingestion from a single `usage.json` reader to a complete iCloud-driven data pipeline that powers all iOS screens (current usage, history, and derived summary states) without direct API reads.
- `icloud-history-sync`: extend history sync expectations so iOS can consume mirrored `usage-history.json` as a first-class read source for activity/history experiences.

## Impact

- Affected targets: `ClaudeTracker/` (iOS), `Shared/` (shared read models and presentation-safe DTOs).
- Likely touched components: `iCloudUsageReader`, `ContentView`, app navigation structure, history/data stores, and iOS settings UI.
- Dependencies/systems: iCloud Drive document coordination, `NSMetadataQuery`, local decode/transform logic, WatchConnectivity relay contracts.
- Risk areas: stale/missing iCloud files, large history payload rendering on iPhone, and maintaining consistent parity as macOS evolves.
