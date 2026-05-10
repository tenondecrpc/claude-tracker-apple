## Purpose

Define macOS authentication for Tempo usage polling.

## Requirements

### Requirement: macOS OAuth PKCE sign-in via browser
The macOS app SHALL authenticate users via OAuth PKCE by opening the authorization URL in the default browser using `NSWorkspace.shared.open()`. The authorization URL SHALL use the parameters from `docs/APIS.md`: client ID `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, redirect URI `https://platform.claude.com/oauth/code/callback`, scopes `user:profile user:inference`, and PKCE method `S256`.

#### Scenario: OAuth flow starts
- **WHEN** the user needs to sign in through Tempo OAuth
- **THEN** the app opens `https://claude.ai/oauth/authorize` with PKCE challenge and random state

#### Scenario: OAuth code exchange succeeds
- **WHEN** the user submits a valid `<code>#<state>` string
- **THEN** the app exchanges the code for tokens and stores Tempo OAuth credentials in the macOS Keychain

#### Scenario: OAuth state is required
- **WHEN** the submitted code is missing the `#<state>` fragment or the state does not match the pending state
- **THEN** the app rejects the callback and clears pending OAuth state

### Requirement: Tempo OAuth credentials are the preferred auth source
The macOS app SHALL prefer Tempo's own OAuth credentials over Claude Code CLI credentials. Tempo OAuth credentials SHALL be stored in the macOS Keychain with service `com.tenondev.tempo.claude.oauth` and account `credentials`.

#### Scenario: Valid Tempo OAuth credentials exist
- **WHEN** `CredentialStore.load()` returns credentials whose access token is valid
- **THEN** the app restores `authSource = webOAuth` and starts polling without reading Claude Code CLI credentials for the request

#### Scenario: Tempo OAuth credentials are expired
- **WHEN** stored Tempo OAuth credentials exist but the access token is expired
- **THEN** the app refreshes only Tempo OAuth credentials using Tempo's stored refresh token, saves the refreshed credentials to Keychain, and restores `authSource = webOAuth`

#### Scenario: Tempo OAuth refresh fails permanently
- **WHEN** the Tempo OAuth refresh endpoint returns `invalid_grant` or 401
- **THEN** Tempo deletes only its own credentials and returns to the sign-in flow

### Requirement: Claude Code CLI credentials are read-only fallback credentials
If Tempo OAuth credentials are unavailable or cannot be restored, the macOS app MAY read the Claude Code CLI Keychain item `Claude Code-credentials` only after the user explicitly chooses the CLI fallback. Tempo SHALL only use the CLI access token if it is fresh. Tempo SHALL NOT use Claude Code's refresh token, write to the Claude Code Keychain item, delete the Claude Code Keychain item, or attempt to repair the Claude Code terminal session.

#### Scenario: Fresh CLI access token exists
- **WHEN** no valid Tempo OAuth credentials are available, the user explicitly chooses the CLI fallback, and `ClaudeCodeKeychainReader.loadTokens(allowUserInteraction: true)` returns a fresh non-empty access token
- **THEN** the app restores `authSource = cliSession` and may issue usage API requests with that access token

#### Scenario: CLI access token is expired
- **WHEN** no valid Tempo OAuth credentials are available and Claude Code CLI credentials exist but the access token is expired
- **THEN** Tempo does not refresh the CLI token and starts the Tempo OAuth sign-in flow instead

#### Scenario: CLI Keychain item is absent
- **WHEN** no valid Tempo OAuth credentials are available and the Claude Code Keychain item is not found
- **THEN** Tempo starts the Tempo OAuth sign-in flow

#### Scenario: CLI-sourced request returns 401
- **WHEN** a request using `authSource = cliSession` returns HTTP 401
- **THEN** Tempo does not use the CLI refresh token and does not write any Claude Code credential data

### Requirement: Usage requests prefer Tempo OAuth over CLI fallback
Authenticated usage requests SHALL use Tempo OAuth credentials first. The CLI access token SHALL be used only when Tempo OAuth credentials are unavailable.

#### Scenario: Both credential sources are available
- **WHEN** Tempo OAuth credentials and a fresh Claude Code CLI access token both exist
- **THEN** the request uses Tempo OAuth credentials and logs `source=webOAuth`

#### Scenario: Explicit CLI fallback uses fresh CLI credentials
- **WHEN** Tempo OAuth credentials are unavailable, the user explicitly chose the CLI fallback, and the Claude Code CLI access token is fresh
- **THEN** the request uses the CLI access token and logs `source=cliSession`

#### Scenario: No credential source is available
- **WHEN** Tempo OAuth credentials are unavailable and the user has not explicitly chosen the CLI fallback
- **THEN** no usage polling starts and the user is prompted to sign in through Tempo OAuth

### Requirement: Sign-out isolates Tempo from Claude Code
Tempo sign-out SHALL clear only Tempo-owned authentication state and polling state. It SHALL NOT delete, refresh, or otherwise modify Claude Code credentials.

#### Scenario: User signs out of Tempo
- **WHEN** `MacOSAPIClient.signOut()` runs
- **THEN** Tempo deletes its own Keychain credentials, clears local auth state, clears persisted rate-limit backoff, stops polling, and presents the welcome window

#### Scenario: User signs out of Claude Code
- **WHEN** Claude Code removes the `Claude Code-credentials` Keychain item but Tempo OAuth credentials remain valid
- **THEN** Tempo restores and polls with `authSource = webOAuth`

### Requirement: Claude Code account label is display-only
The app SHALL read `~/.claude.json` to extract the user's email address or display name from the `oauthAccount` object. This value is display-only and SHALL NOT be treated as authorization for Tempo API requests.

#### Scenario: Claude Code config found
- **WHEN** the app reads `~/.claude.json` and finds `oauthAccount.emailAddress`
- **THEN** the email may be displayed in signed-in or welcome surfaces

#### Scenario: Claude Code config not found
- **WHEN** `~/.claude.json` does not exist or has no `oauthAccount`
- **THEN** Tempo still authenticates solely through Tempo OAuth or fresh CLI fallback credentials
