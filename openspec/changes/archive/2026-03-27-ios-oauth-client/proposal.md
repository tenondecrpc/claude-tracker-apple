## Why

The watchOS usage ring currently shows mocked data (`isMocked: true`, hardcoded 42%). This change wires up the real Anthropic OAuth API so the ring reflects the user's actual 5-hour and 7-day utilization. It is Phase 1 on Track A and unblocks Phase 2 (watch receives real `UsageState`).

## What Changes

- **New** `AnthropicAPIClient.swift` (iOS target) - OAuth PKCE authentication via `ASWebAuthenticationSession`, access/refresh token storage in iOS Keychain, auto-refresh before expiry, exponential backoff on 429
- **New** `UsageStatePoller.swift` (iOS target) - polls `GET /api/oauth/usage` every 15 minutes, maps `five_hour`/`seven_day` response fields to `UsageState` (divides utilization 0–100 → 0–1), handles reset-timestamp reconciliation
- **New** `WatchRelayManager.swift` (iOS target, initial version) - activates `WCSession`, sends `UsageState` via `transferUserInfo`, cancels stale queued transfers before each new send
- **New** `ContentView.swift` (iOS target) - minimal sign-in screen shown before authentication; transitions to "connected" state once OAuth completes
- **Wiring** - all three components started on `applicationDidBecomeActive` in the iOS app entry point

## Capabilities

### New Capabilities

- `anthropic-oauth`: PKCE sign-in flow, token lifecycle (storage, refresh, revocation)
- `usage-polling`: 15-minute polling of `/api/oauth/usage`, response mapping, 429 backoff
- `watch-relay`: WatchConnectivity session management and `UsageState` delivery to watch

### Modified Capabilities

- `watch-dashboard`: the mock badge requirement changes - `isMocked` flag is now set to `false` by the relay, causing the `⚠ mock` badge to disappear when real data arrives

## Impact

- **New files**: `Tempo/AnthropicAPIClient.swift`, `Tempo/UsageStatePoller.swift`, `Tempo/WatchRelayManager.swift`, `Tempo/ContentView.swift`
- **iOS target** only - no changes to Watch Extension or Shared targets in this phase
- **New capability**: `ASWebAuthenticationSession` (no entitlement needed, built into UIKit)
- **New capability**: Keychain access - requires `Keychain Sharing` or standard `SecItem` calls (no entitlement needed for app's own keychain)
- **API reference**: `docs/APIS.md` - all endpoint URLs, response shapes, and OAuth parameters confirmed in Phase 0
