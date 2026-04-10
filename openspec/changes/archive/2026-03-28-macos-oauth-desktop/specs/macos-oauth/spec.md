## ADDED Requirements

### Requirement: macOS OAuth PKCE sign-in via browser
The macOS app SHALL authenticate users via OAuth PKCE by opening the authorization URL in the default browser using `NSWorkspace.shared.open()`. The authorization URL SHALL use the same parameters as `docs/APIS.md`: client ID `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, redirect URI `https://platform.claude.com/oauth/code/callback`, scopes `user:profile user:inference`, method `S256`.

#### Scenario: User initiates sign-in
- **WHEN** the user clicks "Sign in with Claude Code" in the menu bar app and no valid credentials exist
- **THEN** the default browser opens the Anthropic authorization URL with PKCE parameters

#### Scenario: User pastes authorization code
- **WHEN** the user pastes a `<code>#<state>` string into the app's text field and clicks Submit
- **THEN** the app extracts the code (before `#`) and state (after `#`), validates state matches, and exchanges them for tokens via POST to `https://platform.claude.com/v1/oauth/token`

#### Scenario: Token exchange succeeds
- **WHEN** the token exchange returns `access_token`, `refresh_token`, and `expires_in`
- **THEN** all credentials are written to `~/.config/tempo-for-claude/credentials.json` with file permissions `0600` and the app transitions to authenticated state

### Requirement: Credentials stored in file with restricted permissions
Access token, refresh token, expiration date, and scopes SHALL be stored as JSON at `~/.config/tempo-for-claude/credentials.json`. The file SHALL have permissions `0600`. The directory SHALL have permissions `0700`. Credentials SHALL never be stored in `UserDefaults`, iCloud, or any shared location.

#### Scenario: Credentials file created on first sign-in
- **WHEN** OAuth token exchange succeeds and `~/.config/tempo-for-claude/` does not exist
- **THEN** the directory is created with permissions `0700` and `credentials.json` is written with permissions `0600`

#### Scenario: Credentials survive app restart
- **WHEN** the macOS app is quit and relaunched
- **THEN** credentials are read from `credentials.json` and the user remains authenticated without re-signing-in

### Requirement: Auto-restore session on launch
On launch, the macOS app SHALL check if `~/.config/tempo-for-claude/credentials.json` exists with a valid (non-expired) access token. If valid credentials are found, the app SHALL skip the sign-in UI and begin polling immediately.

#### Scenario: Valid credentials found on launch
- **WHEN** the app launches and `credentials.json` contains a non-expired `access_token`
- **THEN** the app transitions directly to authenticated state and starts polling

#### Scenario: Expired credentials trigger refresh
- **WHEN** the app launches and `credentials.json` contains an expired `access_token` but a valid `refresh_token`
- **THEN** the app refreshes the token, updates `credentials.json`, and starts polling

#### Scenario: No credentials found
- **WHEN** the app launches and `credentials.json` does not exist or is empty
- **THEN** the app shows the sign-in UI

### Requirement: Access token auto-refreshed on 401
The app SHALL refresh the access token using the refresh token when an API call returns HTTP 401. On permanent refresh failure (`invalid_grant` or repeated 401), the app SHALL delete `credentials.json` and return to unauthenticated state.

#### Scenario: 401 forces refresh and retry
- **WHEN** an API call returns HTTP 401
- **THEN** the client refreshes the token, updates `credentials.json`, and replays the request exactly once

#### Scenario: Refresh fails permanently
- **WHEN** the refresh token endpoint returns `invalid_grant` or repeated 401
- **THEN** `credentials.json` is deleted and the app shows the sign-in screen

### Requirement: Display Claude Code account info
The app SHALL read `~/.claude/.claude.json` to extract the user's email address or display name from the `oauthAccount` object. This is used for display purposes only (e.g., showing "Signed in as cristian@example.com" in the menu).

#### Scenario: Claude Code config found
- **WHEN** the app reads `~/.claude/.claude.json` and finds `oauthAccount.emailAddress`
- **THEN** the email is displayed in the menu bar status area

#### Scenario: Claude Code config not found
- **WHEN** `~/.claude/.claude.json` does not exist or has no `oauthAccount`
- **THEN** the app falls back to showing "Signed in" without an email

### Requirement: Sign-out clears stored credentials
The app SHALL provide a sign-out action that deletes `credentials.json` and returns the app to unauthenticated state, stopping all polling.

#### Scenario: User signs out
- **WHEN** the user clicks "Sign Out" in the menu
- **THEN** `credentials.json` is deleted, polling stops, and the sign-in UI is shown
