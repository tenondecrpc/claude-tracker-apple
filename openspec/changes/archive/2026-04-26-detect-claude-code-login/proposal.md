## Why

Tempo is positioned as a companion to Claude Code, but its sign-in flow treats Anthropic web OAuth as the only authentication path and ignores the fact that the user is almost always already signed in to Claude Code on the same Mac. The welcome window's "Sign in with Claude Code" button currently only checks Tempo's own stored credentials (`MacOSAPIClient.tryRestoreSession`), not whether Claude Code itself has an active session. After the user signs out, the system needs an explicit signal to surface the welcome window again instead of falling into the unauthenticated menu state. And the existing `ClaudeCodeProfile.load()` decoder in `Tempo macOS/MacOSAPIClient.swift:54-62` reads `~/.claude/.claude.json`, but Claude Code actually stores its profile at `~/.claude.json` (verified on the developer's machine), so the detection that `MacAuthState.accountEmail` already wires up has been silently broken on every install.

This change wires a real "Claude Code session" check into the welcome flow, formalizes the sign-out -> welcome-window transition with an explicit flag, and folds in the path-fix bug so detection actually works. The reference open-source project `claude-usage-bar` (`/Users/tenonde/Projects/open-sources/claude-usage-bar`) uses the same OAuth handshake as Tempo (identical `client_id`, scopes, endpoints, beta header) and reads `~/.claude.json` from `UsageService.swift:325-340` for label purposes - we follow the same pattern.

## What Changes

- **Fix path bug**: change `ClaudeCodeProfile.load()` in `Tempo macOS/MacOSAPIClient.swift:54-62` to read `~/.claude.json` instead of `~/.claude/.claude.json`, matching the actual on-disk location and the reference implementation in `claude-usage-bar` (`UsageService.swift:325-340`). This single-line fix also unblocks the existing post-sign-in account-label feature wired into `MacAuthState.accountEmail`.
- **Define "active Claude Code session"**: SHALL mean `~/.claude.json` exists, is readable, and contains a non-empty `oauthAccount.emailAddress` or `oauthAccount.displayName`. The check SHALL NOT touch the macOS Keychain item `Claude Code-credentials` (the sandbox prevents cross-app keychain reads; see Design > Decision 1).
- **Welcome window "Sign in with Claude Code" button - new flow** (replaces the current restore-then-OAuth flow at `Tempo macOS/WelcomeWindow.swift:57-74`):
  1. First, check whether an active Claude Code session exists (per the definition above).
  2. If a Claude Code session exists, attempt `tryRestoreSession()` first; if Tempo already has valid stored credentials from a prior handshake, restore and dismiss the welcome window.
  3. If a Claude Code session exists but Tempo has no stored credentials yet, start the existing OAuth flow (`startOAuthFlow()`). The button label and copy SHALL communicate that we detected the user's Claude Code account.
  4. If NO Claude Code session exists, start the existing OAuth flow directly (the "login directo con la API de Anthropic en la web" path).
- **Surface detected Claude Code account**: when a Claude Code session is detected, the welcome window SHALL render the detected email (or display name) under the button so the user understands which account is about to be authorized.
- **Explicit logout -> welcome-window transition**: `MacOSAPIClient.signOut()` already sets `MacAuthState.requiresExplicitSignIn = true`, but no surface acts on it. This change SHALL make the macOS coordinator (`Tempo macOS/TempoMacApp.swift`) observe `requiresExplicitSignIn` and open the `welcome` window when it becomes true (and close any open menu surfaces that depend on the authenticated state). The flag SHALL be cleared once the welcome window is presented (or the user re-authenticates).
- **Out of scope (explicitly)**:
  - Reading `Claude Code-credentials` from macOS Keychain or otherwise importing Claude Code's tokens. Sandboxed Tempo cannot do this. Documented as a non-goal in the design.
  - Adding the `https://api.anthropic.com/api/oauth/userinfo` remote-profile fallback that `claude-usage-bar` uses (`UsageService.swift:299-322`). Useful follow-up, but does not block this user-facing change.
  - Replacing Tempo's OAuth client ID, redirect URI, scopes, token endpoint, or stored credential location.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `macos-oauth`: adds requirements covering (a) the Claude-Code-session-aware welcome flow, (b) the explicit logout -> welcome-window transition, and (c) the corrected path for Claude Code profile reads. Existing requirements (OAuth PKCE flow, file-based credential storage, token refresh, sign-out, account-info display) are preserved with the path correction.

## Impact

- **Code**:
  - `Tempo macOS/MacOSAPIClient.swift`: fix `~/.claude/.claude.json` -> `~/.claude.json`; promote the existing private `ClaudeCodeProfile` (or introduce a sibling `DetectedClaudeAccount` value type) so views and the coordinator can call it; add a small helper such as `static var hasActiveClaudeCodeSession: Bool`.
  - `Tempo macOS/WelcomeWindow.swift`: replace the current restore-then-OAuth body of the "Sign in with Claude Code" button with the new four-step decision tree; render the detected email under the button when present.
  - `Tempo macOS/SignInView.swift` (`NotSignedInMenuView`): same Claude-Code-aware affordance on the menu bar popover so the two surfaces stay consistent.
  - `Tempo macOS/TempoMacApp.swift` (the `MacAppCoordinator` and the `WindowGroup(id: "welcome")` setup): observe `MacAuthState.requiresExplicitSignIn` and open the welcome window in response, closing the unauthenticated popover surface if present.
- **APIs**: none. No new network calls, no new endpoints.
- **Entitlements / Sandbox**: unchanged. Reading `~/.claude.json` is a plain home-directory file read; the reference `claude-usage-bar` performs the same read with no entitlement changes.
- **Security**: no change to credential surface area. Tempo never reads Claude Code's Keychain item, never imports Claude Code's tokens, and the detected email is treated as advisory UI only (the OAuth handshake remains the source of truth for who is actually signed in to Tempo).
- **Side effect (positive)**: the path fix re-enables the post-sign-in `MacAuthState.accountEmail` label that has been silently broken; users who upgrade and are already signed in will see their account email appear in the menu for the first time.
- **Risk**: low. Worst-case failure mode is that detection silently fails and the button falls through to today's web-OAuth flow with no user-visible regression.
