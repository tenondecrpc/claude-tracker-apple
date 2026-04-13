## 1. AnthropicAPIClient - Keychain Helpers

- [x] 1.1 Create `Tempo/AnthropicAPIClient.swift` with a `KeychainStore` helper: `save(token:forKey:)`, `load(key:) -> String?`, `delete(key:)` using `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete` with `kSecAttrAccessibleAfterFirstUnlock`
- [x] 1.2 Define Keychain key constants: `"anthropic.access_token"`, `"anthropic.refresh_token"`

## 2. AnthropicAPIClient - PKCE & Token Exchange

- [x] 2.1 Implement `generatePKCE() -> (verifier: String, challenge: String)`: 32 random bytes → base64URL verifier; SHA256(verifier) → base64URL challenge
- [x] 2.2 Implement `buildAuthorizationURL(challenge: String, state: String) -> URL` using confirmed parameters from `docs/APIS.md` (client ID, redirect URI, scopes, `code=true`)
- [x] 2.3 Implement `signIn() async throws` using `ASWebAuthenticationSession` - open authorization URL, await callback, parse `<code>#<state>` from the result
- [x] 2.4 Implement `exchangeCode(_ code: String, verifier: String, state: String) async throws -> (accessToken: String, refreshToken: String)` - POST to `https://platform.claude.com/v1/oauth/token` with confirmed JSON body
- [x] 2.5 Implement `refreshAccessToken() async throws -> String` - POST refresh grant to token endpoint; on `invalid_grant` / persistent 401: call `signOut()` and throw

## 3. AnthropicAPIClient - Authenticated Requests

- [x] 3.1 Implement `authenticatedRequest(for url: URL) async throws -> Data` - loads token from Keychain, calls `refreshIfNeeded()` first, adds `Authorization: Bearer` and `anthropic-beta: oauth-2025-04-20` headers, retries once on 401
- [x] 3.2 Implement `signOut()` - deletes both Keychain entries, sets `isAuthenticated = false`, calls `onSignOut` callback
- [x] 3.3 Add `@Observable @MainActor` class wrapper `AuthState` with `isAuthenticated: Bool` property; update it on sign-in and sign-out

## 4. UsageStatePoller

- [x] 4.1 Create `Tempo/UsageStatePoller.swift` as `@Observable @MainActor final class`
- [x] 4.2 Implement `fetchUsage() async throws -> UsageState` - calls `AnthropicAPIClient.authenticatedRequest` for `https://api.anthropic.com/api/oauth/usage`, decodes JSON, maps `five_hour.utilization / 100` → `utilization5h`, `seven_day.utilization / 100` → `utilization7d`, parses ISO 8601 `resets_at` with fractional seconds support
- [x] 4.3 Implement reset-timestamp reconciliation: if `resets_at` is null, retain previous `resetAt5h`; if `utilization5h` drops from >0 to ~0, discard previous timestamp
- [x] 4.4 Implement `start()` - fires a poll immediately, then schedules a `Timer` every 900 seconds (15 min); `stop()` invalidates the timer
- [x] 4.5 Implement 429 backoff: on HTTP 429, read `Retry-After` header, apply `min(max(retryAfter ?? currentInterval, currentInterval * 2), 3600)`, resume normal interval after next success

## 5. WatchRelayManager

- [x] 5.1 Create `Tempo/WatchRelayManager.swift` as `NSObject` + `WCSessionDelegate`
- [x] 5.2 Implement `activate()` - sets `WCSession.default.delegate = self`, calls `WCSession.default.activate()`; guard with `WCSession.isSupported()`
- [x] 5.3 Implement required iOS delegate methods: `activationDidCompleteWith`, `sessionDidBecomeInactive`, `sessionDidDeactivate` (re-activates)
- [x] 5.4 Implement `send(_ state: UsageState)` - cancel outstanding `"UsageState"` transfers, encode state as `[String: Any]` with `"type": "UsageState"` discriminator, call `transferUserInfo`
- [x] 5.5 Implement `UsageState.toUserInfo() -> [String: Any]` extension: encode `utilization5h`, `utilization7d` as `Double`; `resetAt5h`, `resetAt7d` as `TimeInterval` (`timeIntervalSince1970`); `isMocked` as `Bool`

## 6. iOS ContentView & App Wiring

- [x] 6.1 Create `Tempo/ContentView.swift` - show "Sign in with Claude" button when `!authState.isAuthenticated`; show "Connected ✓" + sign-out button when authenticated
- [x] 6.2 Wire `applicationDidBecomeActive` (or `ScenePhase.active`) to call `poller.start()` if authenticated; call `relay.activate()` unconditionally at launch
- [x] 6.3 On successful sign-in completion, call `poller.start()` immediately; on sign-out, call `poller.stop()`
- [x] 6.4 Connect poller's `onUsageState` callback to `relay.send(_:)`

## 7. Verification

- [ ] 7.1 Sign in via OAuth → confirm tokens written to Keychain (use Xcode memory debugger or log key presence without logging values)
- [ ] 7.2 Confirm `GET /api/oauth/usage` fires → `UsageState` logged to console with real `utilization5h` / `utilization7d` values and `isMocked: false`
- [ ] 7.3 Confirm `transferUserInfo` called → check Xcode console for WCSession delivery log
- [ ] 7.4 Build all targets - zero compiler errors  ← requires Xcode
