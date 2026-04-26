## MODIFIED Requirements

### Requirement: Display Claude Code account info
The app SHALL read `~/.claude.json` to extract the user's email address or display name from the `oauthAccount` object. This is used for display purposes only (e.g., showing "Signed in as cristian@example.com" in the menu).

#### Scenario: Claude Code config found
- **WHEN** the app reads `~/.claude.json` and finds `oauthAccount.emailAddress`
- **THEN** the email is displayed in the menu bar status area

#### Scenario: Claude Code config not found
- **WHEN** `~/.claude.json` does not exist or has no `oauthAccount`
- **THEN** the app falls back to showing "Signed in" without an email

## ADDED Requirements

### Requirement: Definition of an active Claude Code session
The macOS app SHALL consider a Claude Code session "active" when, and only when, `~/.claude.json` is readable AND its `oauthAccount` object contains a non-empty `emailAddress` or non-empty `displayName`. The check SHALL NOT read the macOS Keychain item `Claude Code-credentials`. The check SHALL NOT depend on Tempo's own stored credentials. The check SHALL be implemented as a single source of truth (e.g., `DetectedClaudeAccount.isActive`) reused by every surface that needs it.

#### Scenario: Active session
- **WHEN** `~/.claude.json` exists and `oauthAccount.emailAddress = "user@example.com"`
- **THEN** the active-Claude-Code-session check returns true

#### Scenario: Active session via display name
- **WHEN** `~/.claude.json` exists and `oauthAccount.displayName = "User"` with no `emailAddress`
- **THEN** the active-Claude-Code-session check returns true

#### Scenario: No Claude Code config
- **WHEN** `~/.claude.json` does not exist or is unreadable
- **THEN** the active-Claude-Code-session check returns false

#### Scenario: Empty oauthAccount
- **WHEN** `~/.claude.json` exists but has no `oauthAccount` object, or both `emailAddress` and `displayName` are empty
- **THEN** the active-Claude-Code-session check returns false

#### Scenario: Detection never reads Keychain
- **WHEN** the active-Claude-Code-session check runs
- **THEN** no call to `SecItemCopyMatching` or any Keychain API is made and no Keychain access prompt is shown

### Requirement: Welcome-window "Sign in with Claude Code" button decision tree
The welcome window's "Sign in with Claude Code" button SHALL implement the following decision tree on tap:

1. Evaluate the active-Claude-Code-session check.
2. If active AND `tryRestoreSession()` succeeds, transition to authenticated state and dismiss the welcome window.
3. If active AND `tryRestoreSession()` fails (no Tempo credentials yet, or refresh failed), start the existing OAuth PKCE flow via `MacOSAPIClient.startOAuthFlow()`.
4. If not active, start the existing OAuth PKCE flow directly via `MacOSAPIClient.startOAuthFlow()` without attempting to restore.

The button SHALL never gate Tempo authentication on the active-Claude-Code-session signal alone; tokens always come from the OAuth handshake or from `~/.config/tempo-for-claude/credentials.json`.

#### Scenario: Active session and Tempo creds exist
- **WHEN** the user clicks "Sign in with Claude Code" AND a Claude Code session is active AND Tempo has valid stored credentials
- **THEN** the app restores the session, marks the user authenticated, and dismisses the welcome window without opening the browser

#### Scenario: Active session, no Tempo creds
- **WHEN** the user clicks "Sign in with Claude Code" AND a Claude Code session is active AND Tempo has no valid stored credentials
- **THEN** the app starts the OAuth PKCE flow (browser opens to the Anthropic authorization URL) and transitions into the awaiting-code state

#### Scenario: No Claude Code session
- **WHEN** the user clicks "Sign in with Claude Code" AND no Claude Code session is active
- **THEN** the app starts the OAuth PKCE flow directly without attempting `tryRestoreSession()`

#### Scenario: OAuth still authoritative
- **WHEN** an active Claude Code session is detected
- **THEN** the app does not mark the user as authenticated, does not write to `credentials.json`, and does not begin polling until either `tryRestoreSession()` succeeds with stored credentials OR an OAuth handshake completes

### Requirement: Welcome window surfaces detected Claude Code account label
When the welcome window is presented and the active-Claude-Code-session check returns true, the welcome window SHALL render the detected `emailAddress` (preferred) or `displayName` as a caption beneath the "Sign in with Claude Code" button. When the check returns false, no caption SHALL be shown.

#### Scenario: Caption shown when active
- **WHEN** the welcome window is presented AND `~/.claude.json` has `oauthAccount.emailAddress = "user@example.com"`
- **THEN** the welcome window renders a caption such as "Detected: user@example.com" beneath the button

#### Scenario: Caption hidden when inactive
- **WHEN** the welcome window is presented AND no Claude Code session is active
- **THEN** no detected-account caption is rendered and the existing button copy is shown

### Requirement: Sign-out routes the user back to the welcome window
After `MacOSAPIClient.signOut()` runs, the macOS app SHALL automatically present the welcome window (`WindowGroup(id: "welcome")`) without requiring the user to navigate manually. This SHALL be implemented by having the macOS coordinator observe `MacAuthState.requiresExplicitSignIn` and call `openWindow(id: "welcome")` when it transitions to true. Any open menu bar popover whose state depends on the authenticated session SHALL be closed. The flag SHALL be cleared once the welcome window is presented so it does not re-trigger on subsequent state changes.

#### Scenario: Sign-out opens welcome window
- **WHEN** the user clicks "Sign Out" from any signed-in surface
- **THEN** `signOut()` clears credentials, the welcome window opens automatically, and `MacAuthState.requiresExplicitSignIn` is reset to false after presentation

#### Scenario: Stale popover closed
- **WHEN** the menu bar popover is open with authenticated content AND the user signs out
- **THEN** the popover closes (or transitions to its unauthenticated body) and the welcome window appears in front

#### Scenario: Welcome reopens with fresh detection
- **WHEN** the welcome window is auto-opened after sign-out
- **THEN** the active-Claude-Code-session check runs fresh, so a Claude Code session that is still active is detected and the button shows the detected caption

### Requirement: Detection touches no credential surface and adds no entitlements
The active-Claude-Code-session detection SHALL only read `~/.claude.json`. It SHALL NOT read the macOS Keychain item `Claude Code-credentials`, SHALL NOT introduce new entitlements, SHALL NOT write to `~/.claude.json` or anything under `~/.claude/`, and SHALL NOT add new network calls.

#### Scenario: No Keychain access
- **WHEN** detection runs at any point in the app lifecycle
- **THEN** no Keychain query for Claude Code's credentials is issued

#### Scenario: No new entitlements required
- **WHEN** the change is implemented
- **THEN** `Tempo macOS/Tempo macOS.entitlements` is unchanged from before the change

#### Scenario: No write to Claude Code's data
- **WHEN** detection runs and the user clicks the welcome-window button
- **THEN** no file under `~/.claude/` and not `~/.claude.json` is created, modified, or deleted by Tempo
