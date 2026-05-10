## MODIFIED Requirements

### Requirement: macOS OAuth PKCE sign-in adds an account
The macOS app SHALL authenticate users via OAuth PKCE by opening the authorization URL in the default browser using `NSWorkspace.shared.open()`. The authorization URL SHALL use the parameters from `docs/APIS.md`: client ID `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, redirect URI `https://platform.claude.com/oauth/code/callback`, scopes `user:profile user:inference`, and PKCE method `S256`.

Each successful sign-in SHALL create a new entry in `AccountRegistry` with `accountId` derived from the authenticated user's email. Sign-in SHALL NEVER replace an existing account whose id differs from the incoming one.

#### Scenario: OAuth flow starts
- **WHEN** the user needs to sign in through Tempo OAuth
- **THEN** the app opens `https://claude.ai/oauth/authorize` with PKCE challenge and random state

#### Scenario: OAuth code exchange succeeds and adds account
- **WHEN** the user submits a valid `<code>#<state>` string for an email not already in the registry
- **THEN** the app exchanges the code for tokens, derives `accountId` from the profile email, stores the credentials in the macOS Keychain under that `accountId`, and adds the new `Account` to the registry

#### Scenario: Sign-in for an already-registered email updates tokens
- **WHEN** OAuth completes for an email whose accountId already exists in the registry
- **THEN** the app updates that account's Keychain credentials in place and SHALL NOT duplicate the account in the registry

#### Scenario: OAuth state is required
- **WHEN** the submitted code is missing the `#<state>` fragment or the state does not match the pending state
- **THEN** the app rejects the callback and clears pending OAuth state

### Requirement: Tempo OAuth credentials are preferred per-account auth source
The macOS app SHALL prefer Tempo's own OAuth credentials over Claude Code CLI credentials on a per-account basis. For each account, Tempo OAuth credentials SHALL be stored in the macOS Keychain under service `com.tenondev.tempo.claude.oauth` with `kSecAttrAccount: <accountId>`.

#### Scenario: Valid Tempo OAuth credentials exist for account
- **WHEN** `CredentialStore.load(for: accountId)` returns credentials whose access token is valid
- **THEN** the app restores `authSource = webOAuth` for that accountId and starts polling for that account without reading Claude Code CLI credentials for its requests

#### Scenario: Tempo OAuth credentials are expired
- **WHEN** stored Tempo OAuth credentials exist for an accountId but the access token is expired
- **THEN** the app refreshes only that account's Tempo OAuth credentials using the stored refresh token, saves the refreshed credentials to Keychain under the same accountId, and keeps `authSource = webOAuth` for that accountId

#### Scenario: Tempo OAuth refresh fails permanently
- **WHEN** the Tempo OAuth refresh endpoint returns `invalid_grant` or 401 for an accountId
- **THEN** Tempo deletes only that account's Keychain credentials, removes the account from the registry (moving its iCloud data under `retired/`), and reassigns `activeAccountId` if necessary

### Requirement: Claude Code CLI credentials are read-only fallback for the primary account only
If no registered account has valid Tempo OAuth credentials, the macOS app MAY read the Claude Code CLI Keychain item `Claude Code-credentials` as a fallback. The CLI-derived request SHALL be attributed to the accountId that matches the CLI profile's email. Tempo SHALL only use the CLI access token if it is fresh. Tempo SHALL NOT use Claude Code's refresh token, write to the Claude Code Keychain item, delete the Claude Code Keychain item, or attempt to repair the Claude Code terminal session.

#### Scenario: Fresh CLI access token exists for known accountId
- **WHEN** no valid Tempo OAuth credentials exist for any registered account and `ClaudeCodeKeychainReader.loadTokens()` returns a fresh non-empty access token for an email that matches an existing accountId
- **THEN** the app uses the CLI access token for that accountId's requests and logs `source=cliSession`

#### Scenario: Fresh CLI access token for unknown account
- **WHEN** the CLI access token's email does not match any registered accountId
- **THEN** the app offers to add it as a new account and does not silently attribute its polling to an unrelated account

#### Scenario: CLI access token is expired
- **WHEN** no valid Tempo OAuth credentials are available and the CLI access token is expired
- **THEN** Tempo does not refresh the CLI token and instead starts the Tempo OAuth sign-in flow for the affected account

#### Scenario: CLI Keychain item is absent
- **WHEN** no valid Tempo OAuth credentials exist and the Claude Code Keychain item is not found
- **THEN** Tempo starts the Tempo OAuth sign-in flow

#### Scenario: CLI-sourced request returns 401
- **WHEN** a request using `authSource = cliSession` returns HTTP 401
- **THEN** Tempo does not use the CLI refresh token and does not write any Claude Code credential data

### Requirement: Usage requests prefer per-account Tempo OAuth over CLI fallback
Authenticated usage requests SHALL use Tempo OAuth credentials for the target account first. The CLI access token SHALL only be used when the account's Tempo OAuth credentials are unavailable.

#### Scenario: Both credential sources are available for account
- **WHEN** Tempo OAuth credentials and a fresh Claude Code CLI access token both exist for an accountId
- **THEN** the request uses Tempo OAuth credentials for that account and logs `source=webOAuth`

#### Scenario: Only fresh CLI credentials are available
- **WHEN** an account has no Tempo OAuth credentials and the CLI access token is fresh and matches its email
- **THEN** the request uses the CLI access token and logs `source=cliSession`

#### Scenario: No credential source is available
- **WHEN** neither Tempo OAuth credentials nor a fresh CLI access token exist for an account
- **THEN** no usage polling starts for that account and the user is prompted to sign in for that specific account

### Requirement: Sign-out is scoped to a specific account
Tempo sign-out SHALL target a specific accountId chosen by the user. It SHALL clear only that account's authentication state and polling state. It SHALL NOT delete, refresh, or otherwise modify Claude Code credentials.

#### Scenario: User signs out of one account
- **WHEN** `MacOSAPIClient.signOut(for: accountId)` runs for an account in the registry
- **THEN** Tempo deletes that account's Keychain credentials, stops polling for that account, clears that account's persisted rate-limit backoff, removes the account from the registry, and moves its iCloud data under `retired/`

#### Scenario: Sign-out of last account returns to welcome
- **WHEN** the user signs out of the only remaining account
- **THEN** `activeAccountId` becomes `nil`, polling stops entirely, and the welcome window is presented

#### Scenario: User signs out of Claude Code externally
- **WHEN** Claude Code removes the `Claude Code-credentials` Keychain item but Tempo OAuth credentials remain valid for any registered accountId
- **THEN** Tempo continues polling for each such accountId with `authSource = webOAuth`

### Requirement: Claude Code account label is display-only and used for matching
The app SHALL read `~/.claude.json` to extract the user's email address or display name from the `oauthAccount` object. This value is display-only and SHALL NOT be treated as authorization for Tempo API requests. Its email MAY be used to match incoming sessions to an existing accountId.

#### Scenario: Claude Code config found and matches registered account
- **WHEN** the app reads `~/.claude.json` and finds `oauthAccount.emailAddress` that matches an accountId in the registry
- **THEN** sessions ingested while that config is active are tagged with that accountId

#### Scenario: Claude Code config found but no matching account
- **WHEN** `oauthAccount.emailAddress` does not match any registered accountId
- **THEN** ingested sessions are tagged with the `unassigned` bucket and the email is still surfaced in UI for association

#### Scenario: Claude Code config not found
- **WHEN** `~/.claude.json` does not exist or has no `oauthAccount`
- **THEN** Tempo still authenticates solely through per-account Tempo OAuth or fresh CLI fallback credentials
