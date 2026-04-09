## Context

The current iOS target is a lightweight bridge: it watches `usage.json`, shows sync status, and relays `UsageState` to watchOS. The macOS target already contains richer product behavior (usage dashboard, activity/history views, and preferences) and writes usage artifacts to iCloud (`usage.json` and `usage-history.json`).

The requested change is to deliver macOS-equivalent user-facing functionality on iOS while keeping macOS as the producer and iOS as a pure iCloud consumer. Repository constraints also require that shared code in `Shared/` remains model/business logic only (no platform UI, no iCloud plumbing, no WatchConnectivity code).

## Goals / Non-Goals

**Goals:**
- Provide iOS feature parity for core macOS usage experiences: dashboard, activity/history, and settings-oriented controls that are meaningful on iOS.
- Use `ClaudeCodeTheme` tokens consistently across iOS to match Claude visual language.
- Drive all iOS user data from iCloud files written by macOS, not from direct API/OAuth calls.
- Preserve watch relay continuity by continuing to emit watch payloads from iOS as iCloud updates arrive.
- Keep stale/missing sync states explicit and user-actionable.

**Non-Goals:**
- Adding OAuth/authentication flows to iOS.
- Replacing macOS as the source of truth for usage polling.
- Copying macOS-only operational settings that do not apply to iOS (for example launch-at-login or in-app updater controls).
- Rewriting watchOS UI behavior in this change.

## Decisions

### 1) iOS Information Architecture: 3-tab parity shell
Use a `TabView`-based structure with:
- Dashboard: ring-centric current usage and reset timing.
- Activity: history/chart views sourced from iCloud snapshots.
- Settings: iOS-relevant sync/account/status controls and diagnostics.

Rationale:
- Matches macOS mental model (overview + activity + preferences) while respecting iOS navigation norms.
- Keeps critical usage state one tap away and avoids overloading a single scroll screen.

Alternatives considered:
- Single long dashboard screen with sections: rejected due to weak discoverability and poor separation between live metrics, historical analysis, and settings.

### 2) iCloud-first read pipeline: multi-file metadata-driven store
Introduce an iOS read coordinator that tracks both `usage.json` and `usage-history.json` via `NSMetadataQuery` + `NSFileCoordinator`, producing one observable state object consumed by all tabs.

Rationale:
- Ensures every iOS surface is backed by the same snapshot, preventing per-screen divergence.
- Preserves existing iCloud event-driven behavior and download-on-demand semantics.

Alternatives considered:
- Poll file paths on timer: rejected for poorer efficiency, delayed updates, and weaker coordination semantics for ubiquitous files.

### 3) Data normalization boundary in shared models, not views
Add/extend shared model types in `Shared/` for iOS-ready read payloads (for example history decode payload + derived summary metrics), while keeping iCloud access and UI composition in platform targets.

Rationale:
- Keeps transformation logic testable and reusable.
- Aligns with repository rule that `Shared/` contains pure logic/data, not platform integration code.

Alternatives considered:
- Decode and derive directly inside SwiftUI views: rejected due to duplication, harder testing, and view-state coupling.

### 4) Visual parity contract: Claude tokens as single styling source
All iOS screens must use `ClaudeCodeTheme` tokens for backgrounds, cards, text, accents, status colors, chart rails, and ring tracks. iOS remains dark-palette resolved per current theme behavior.

Rationale:
- Maintains consistent brand identity across macOS/iOS/watch surfaces.
- Prevents token drift and ad-hoc color usage as UI grows.

Alternatives considered:
- Mix with default iOS semantic colors: rejected because it weakens parity and introduces inconsistent contrast/brand expression.

### 5) Watch relay continuity: keep current payload contract
Continue relaying `UsageState` to watchOS from iOS using existing `transferUserInfo` behavior. New iOS UI data does not change watch payload format in this change.

Rationale:
- Avoids unnecessary watch protocol churn while delivering iOS parity.
- Reduces rollout risk by isolating iOS UI/data improvements from watch contract changes.

Alternatives considered:
- Expanding watch payload to include history/context: deferred as a separate change.

### 6) Platform-appropriate settings parity
Mirror only relevant preferences/status on iOS (sync health, staleness, data timestamps, iCloud availability, account/connectivity context when available in synced data). Desktop-only controls remain macOS-only.

Rationale:
- Preserves parity of intent without creating dead controls on iOS.

Alternatives considered:
- 1:1 cloning all macOS preference toggles: rejected because several toggles are non-functional or meaningless on iOS.

## Risks / Trade-offs

- [Risk] iCloud partial availability (one file updates before the other) can create transient mismatch.
  → Mitigation: compute and expose per-file freshness plus a combined snapshot status; gate chart rendering when required data is missing.

- [Risk] Large `usage-history.json` payloads can cause jank on older phones.
  → Mitigation: decode off-main-thread, cap in-memory/chart window for rendering, and reuse precomputed derived buckets.

- [Risk] macOS parity expectations may drift as desktop features evolve.
  → Mitigation: document explicit parity scope in specs and keep capability deltas targeted to current macOS behavior.

- [Risk] UI parity may overfit desktop interaction patterns.
  → Mitigation: preserve parity at data/insight level while adopting iOS-native navigation and touch affordances.

## Migration Plan

1. Add iOS read-store extensions for multi-file iCloud ingest while keeping existing status screen code path available.
2. Introduce tab-based iOS shell behind the new read-store output and wire dashboard/activity/settings to it.
3. Validate stale/missing iCloud states and watch relay behavior with real iCloud sync scenarios.
4. Remove legacy iOS-only auth-centric UI paths once parity screens are stable.
5. Ship without changing watch payload schema or macOS polling contract.

Rollback:
- Revert iOS root view to the existing sync-status screen and keep only current `usage.json` handling if parity UI causes regressions.

## Open Questions

- Should iOS surface account email if available from synced data, or keep account identity macOS-only for privacy/minimalism?
- Should iOS Activity parity include every macOS insight card in v1, or prioritize chart + key summary cards first?
