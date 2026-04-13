## Context

The iOS app target (`Tempo/`) is currently empty - no views, no logic. This change builds the three-component iOS backend that powers the usage ring on the watch:

1. `AnthropicAPIClient` - OAuth identity and token lifecycle
2. `UsageStatePoller` - periodic API polling and response mapping
3. `WatchRelayManager` - WatchConnectivity delivery to the watch

All API signatures are confirmed in `docs/APIS.md` (Phase 0 output). No speculation needed.

## Goals / Non-Goals

**Goals:**
- User can sign in with their Claude account from the iOS app
- iOS polls `/api/oauth/usage` every 15 minutes and delivers real `UsageState` to the watch
- Watch mock badge disappears on first successful poll
- Tokens stored securely in Keychain; never `UserDefaults`

**Non-Goals:**
- Phase 2 (watch receives and renders the data) - that's a separate change
- `SessionInfo` relay (Track B, Phase 4) - `WatchRelayManager` is scoped to `UsageState` only this phase
- UI polish on the iOS sign-in screen - functional only

## Decisions

### ASWebAuthenticationSession for OAuth (vs. manual `WKWebView` or `SFSafariViewController`)

`ASWebAuthenticationSession` is the system-standard mechanism for OAuth flows on iOS. It handles the callback URL automatically, shares cookies with Safari (so users already signed into claude.ai may skip re-authentication), and requires no entitlements. The alternative (`SFSafariViewController`) doesn't handle callback interception without a custom URL scheme, which adds complexity. Decision: `ASWebAuthenticationSession`.

**Callback flow**: The authorization redirect lands in the browser. Per Phase 0, the app uses a "paste code" flow - the redirect URL is `https://platform.claude.com/oauth/code/callback` and the user pastes a `<code>#<state>` string. `ASWebAuthenticationSession` is initialized with this redirect URI as the `callbackURLScheme`-less variant; the session completes when the redirect is detected. If Anthropic's callback is browser-only (paste model), we intercept via the `completionHandler` after the user is redirected back.

### Keychain via `SecItem` (vs. third-party wrapper)

Standard `SecItem` API (`SecItemAdd`, `SecItemCopyMatching`, `SecItemUpdate`, `SecItemDelete`) is sufficient for storing two strings (access token, refresh token). No third-party dependency needed. Tokens stored with `kSecAttrAccessibleAfterFirstUnlock` so they're available after the device is unlocked (background app refresh scenarios).

### `transferUserInfo` for WatchConnectivity (vs. `sendMessage`)

`transferUserInfo` queues delivery and survives watch being off-wrist or unreachable. Critical for a polling-based app where iOS may poll while the watch is charging. Stale `UsageState` transfers are pruned before each new send (`outstandingUserInfoTransfers.cancel()`) to avoid a burst of stale snapshots when the watch reconnects. `SessionInfo` transfers (Phase 4) must never be cancelled.

### Timer-based polling via `Timer.scheduledTimer` (vs. `BackgroundAppRefresh`)

Background App Refresh is throttled by iOS and cannot be relied on for a 15-minute interval. A foreground `Timer` fires reliably while the app is active. For background polling, a `BGAppRefreshTask` will be registered - but the MVP only requires the ring to update when the user opens the iOS app. Background refresh is listed as an open question.

### `@Observable` for `AuthState` (vs. `@Published` / `ObservableObject`)

Consistent with the watch extension's existing pattern (`TokenStore` uses `@Observable`). `@Observable` on iOS 17+ eliminates the need for `ObservableObject` + `@Published`.

## Risks / Trade-offs

- **Paste-code callback UX** → The `<code>#<state>` paste flow is unusual. If Anthropic adds a proper deep-link redirect (custom URL scheme), this can be replaced with a one-tap flow. The OAuth client is isolated enough to swap this without touching the poller or relay.
- **Background polling gap** → The ring won't update while the iOS app is backgrounded. Mitigation: register `BGAppRefreshTask` in a follow-up; for MVP the ring updates on next app open.
- **Token expiry while app is backgrounded** → Auto-refresh is triggered proactively before each poll. If the app hasn't been opened and the token expires, the next open triggers a refresh. If refresh fails (e.g. `invalid_grant`), the user is shown the sign-in screen again.
- **`outstandingUserInfoTransfers` prune races** → Cancelling a transfer that's mid-delivery is safe per Apple docs - the system ignores cancelled transfers that already arrived. No data loss risk.

## Open Questions

- **Background polling**: Register `BGAppRefreshTask` now or defer to a polish phase? (Recommendation: defer - MVP is foreground-only)
- **Sign-out**: Should the iOS app provide a sign-out button in Phase 1? (Recommendation: yes - avoids needing a new change just to clear Keychain during development)
