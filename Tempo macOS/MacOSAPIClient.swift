import Foundation
import CryptoKit
import AppKit

// MARK: - MacAuthError

enum MacAuthError: LocalizedError {
    case noToken
    case invalidCallback
    case tokenExchangeFailed
    case refreshFailed
    case rateLimited(retryAfter: TimeInterval?)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .noToken: return "No authentication token. Please sign in."
        case .invalidCallback: return "Invalid authorization callback."
        case .tokenExchangeFailed: return "Failed to exchange authorization code."
        case .refreshFailed: return "Session expired. Please sign in again."
        case .rateLimited(let s): return s.map { "Rate limited. Retry after \(Int($0))s." } ?? "Rate limited."
        case .httpError(let code): return "HTTP error \(code)."
        }
    }
}

// MARK: - MacAuthState

@Observable
@MainActor
final class MacAuthState {
    var isAuthenticated = false
    var isAwaitingCode = false
    var requiresExplicitSignIn = false
    var accountEmail: String?
    var authSource: AuthSource = .none

    enum AuthSource: Equatable {
        case none
        case cliSession
        case webOAuth
    }

    init() {
        // Do NOT check Keychain here -- this runs during app init and would
        // trigger Keychain prompts before the UI is ready. Authentication
        // state is resolved only when the user explicitly signs in via the
        // Welcome window.
        //
        // Pre-login email detection from `~/.claude.json` was removed: under
        // App Sandbox the file is not readable and the value was never
        // populated in production anyway. The active-account email is set
        // by `syncAccountEmail(for:)` after sign-in or restore.
        accountEmail = nil
    }
}

// MARK: - OAuthProfile

/// Account metadata returned by
/// `https://api.anthropic.com/api/oauth/profile`.
///
/// The server returns three top-level objects: `account`, `organization`,
/// and `application`. Tempo only needs to identify the signed-in user
/// across launches, and the canonical key for that is `account.email` -
/// it is the only field consumed downstream (see
/// `AccountIdentifier.canonicalize(email:)`). All other fields are
/// captured below for reference but are intentionally NOT persisted: they
/// either duplicate state already provided by the usage poller
/// (subscription tier, rate limit) or pin Tempo to schema details
/// Anthropic may evolve.
///
/// Server schema observed May 2026:
///
///   account.uuid                            - Anthropic user UUID (not used; email is canonical)
///   account.email                           - Verified email; PRIMARY account identifier
///   account.full_name                       - Display name; preferred when non-empty
///   account.display_name                    - Shorter display name; fallback when full_name is empty
///   account.has_claude_max                  - Max tier flag
///   account.has_claude_pro                  - Pro tier flag
///   account.created_at                      - User creation timestamp (ISO 8601)
///   organization.uuid                       - Org UUID
///   organization.name                       - Org display name
///   organization.organization_type          - e.g. "claude_pro"
///   organization.billing_type               - e.g. "stripe_subscription"
///   organization.rate_limit_tier            - e.g. "default_claude_ai"
///   organization.seat_tier                  - Nullable
///   organization.has_extra_usage_enabled    - Bool
///   organization.subscription_status        - e.g. "active"
///   organization.subscription_created_at    - ISO 8601
///   organization.cc_onboarding_flags        - Object
///   organization.claude_code_trial_ends_at  - Nullable ISO 8601
///   organization.claude_code_trial_duration_days - Nullable Int
///   application.uuid                        - OAuth client UUID
///   application.name                        - e.g. "Claude Code"
///   application.slug                        - e.g. "claude-code"
///
/// Reading the user's email from the local Claude Code state file
/// (`~/.claude.json`) is intentionally not supported: that file lives
/// outside the granted security-scoped bookmark (`~/.claude/`), so the
/// app never has permission to read it under App Sandbox. The OAuth
/// profile endpoint is the sole supported source for the user's email
/// and display name.
struct OAuthProfile: Decodable {
    /// `account.email`. The single source of truth for filtering and
    /// identifying the signed-in user across the app.
    let email: String?

    /// `account.full_name` when non-empty, otherwise `account.display_name`.
    /// Used only for UI labels; never used as an identifier.
    let name: String?

    private struct AccountPayload: Decodable {
        let email: String?
        let full_name: String?
        let display_name: String?
    }

    private struct Envelope: Decodable {
        let account: AccountPayload?
    }

    init(from decoder: Decoder) throws {
        let envelope = try Envelope(from: decoder)
        self.email = envelope.account?.email
        if let full = envelope.account?.full_name, !full.isEmpty {
            self.name = full
        } else {
            self.name = envelope.account?.display_name
        }
    }
}

// MARK: - MacOSAPIClient

@MainActor
final class MacOSAPIClient {

    private enum OAuth {
        static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        static let redirectURI = "https://platform.claude.com/oauth/code/callback"
        static let authorizationEndpoint = "https://claude.ai/oauth/authorize"
        static let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
        static let scopes = "user:profile user:inference"
    }

    private enum API {
        static let betaHeader = "oauth-2025-04-20"
    }

    private enum TokenSource: String {
        case cliSession
        case webOAuth
    }

    let authState: MacAuthState

    /// In-memory store for the set of known Anthropic accounts and the
    /// currently active one. All per-account Keychain writes and reads go
    /// through `CredentialStore` keyed by the `accountId` held here.
    let registry: AccountRegistry

    /// Optional end-to-end removal helper. When injected, `signOut(for:)`
    /// delegates to it to tear down Keychain credentials, the iCloud
    /// per-account directory, the registry entry, and the iCloud mirror in
    /// one call. Callers that do not need sign-out (for example targets
    /// that only use `authenticatedRequest(for:accountId:)`) can omit it
    /// and the class will fall back to a minimal `CredentialStore.delete`
    /// + `registry.remove` pair.
    let removalService: AccountRemovalService?

    /// Notifies the coordinator that an account was signed out, with the
    /// `accountId` that was removed so downstream state (per-account
    /// pollers, widget snapshots, session cache) can be scoped precisely.
    var onSignOut: ((String) -> Void)?

    private var codeVerifier: String?
    private var pendingOAuthState: String?

    /// Single-flight map for Tempo OAuth token refresh, keyed by accountId.
    /// Concurrent callers for the SAME accountId await the same in-flight
    /// refresh; refreshes for DIFFERENT accountIds run independently.
    private var inFlightWebRefresh: [String: Task<String, Error>] = [:]

    init(
        authState: MacAuthState,
        registry: AccountRegistry,
        removalService: AccountRemovalService? = nil
    ) {
        self.authState = authState
        self.registry = registry
        self.removalService = removalService
    }

    // MARK: - PKCE

    private func generatePKCE() -> (verifier: String, challenge: String) {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let hash = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return (verifier, challenge)
    }

    private func buildAuthorizationURL(challenge: String, state: String) -> URL {
        var components = URLComponents(string: OAuth.authorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: OAuth.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: OAuth.redirectURI),
            URLQueryItem(name: "scope", value: OAuth.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    // MARK: - Sign In

    func startOAuthFlow() {
        let (verifier, challenge) = generatePKCE()
        let state = UUID().uuidString
        codeVerifier = verifier
        pendingOAuthState = state
        let authURL = buildAuthorizationURL(challenge: challenge, state: state)
        NSWorkspace.shared.open(authURL)
        authState.isAwaitingCode = true
    }

    func submitOAuthCode(_ rawCode: String) async throws {
        let trimmed = rawCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "#", maxSplits: 1).map(String.init)
        let code = parts[0]

        guard parts.count > 1 else {
            clearPendingOAuth()
            throw MacAuthError.invalidCallback
        }
        guard parts[1] == pendingOAuthState else {
            clearPendingOAuth()
            throw MacAuthError.invalidCallback
        }

        guard let verifier = codeVerifier else {
            clearPendingOAuth()
            throw MacAuthError.invalidCallback
        }

        let tokens = try await exchangeCode(code, verifier: verifier, state: pendingOAuthState ?? "")

        // Derive the accountId + Account metadata from the freshly-signed-in
        // profile. The OAuth profile endpoint
        // (`https://api.anthropic.com/api/oauth/profile`) is the only
        // source consulted; when it does not return an email we fall back
        // to a deterministic synthetic id seeded by the refresh token.
        let account = await makeAccount(from: tokens)

        // Identity convergence (see `docs/AUTH_FLOW.md` - "Identity
        // convergence across CLI and OAuth"): if we resolved a canonical
        // email-backed id AND the registry still carries an older
        // synthetic `cli-local-<hash>` entry that was created during a
        // prior CLI-only launch, migrate it so CLI-first / OAuth-later
        // flows under the same email end up on a single registry row.
        // The `usedEmailBackedId` check guards against a fallback id
        // wiping a real canonical row that already existed.
        let usedEmailBackedId = !account.accountId.hasPrefix("cli-local-")
        if usedEmailBackedId {
            let synthetics = registry.accounts
                .map { $0.accountId }
                .filter { $0.hasPrefix("cli-local-") && $0 != account.accountId }
            for oldId in synthetics {
                DevLog.trace(
                    "AuthTrace",
                    "Migrating synthetic CLI account to OAuth-derived canonical id oldAccountId=\(oldId) newAccountId=\(account.accountId)"
                )
                if let removalService {
                    removalService.removeAccount(accountId: oldId)
                } else {
                    registry.remove(accountId: oldId)
                }
            }
        }

        let credentials = StoredCredentials(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt,
            scopes: OAuth.scopes.components(separatedBy: " ")
        )
        try CredentialStore.save(credentials, for: account.accountId)

        registry.add(account)
        registry.setActive(accountId: account.accountId)

        authState.isAuthenticated = true
        authState.authSource = .webOAuth
        authState.requiresExplicitSignIn = false
        authState.accountEmail = account.email

        DevLog.trace(
            "AuthTrace",
            "OAuth code exchange succeeded source=webOAuth accountId=\(account.accountId) expiresAt=\(tokens.expiresAt)"
        )
        clearPendingOAuth()
    }

    /// Builds an `Account` value for a freshly-completed OAuth exchange.
    /// Fetches `https://api.anthropic.com/api/oauth/profile` with the
    /// just-issued access token, canonicalizes the returned email into an
    /// accountId, and falls back to a synthetic
    /// `cli-local-<hash>` id seeded by the refresh token only when the
    /// profile fetch fails or returns no email.
    private func makeAccount(
        from tokens: (accessToken: String, refreshToken: String, expiresAt: Date)
    ) async -> Account {
        let profile = await fetchOAuthProfile(accessToken: tokens.accessToken)

        if let rawEmail = profile?.email,
           let canonicalId = try? AccountIdentifier.canonicalize(email: rawEmail) {
            let displayName: String = {
                if let name = profile?.name, !name.isEmpty { return name }
                return canonicalId
            }()
            return Account(
                accountId: canonicalId,
                email: canonicalId,
                displayName: displayName,
                createdAt: Date()
            )
        }

        // Fallback: profile endpoint returned no usable email. Derive a
        // synthetic id from the refresh token so repeated sign-ins
        // converge on the same accountId, and label the account with the
        // server-supplied display name when available.
        let fallbackId = AccountIdentifier.cliFallbackAccountId(from: tokens.refreshToken)
        let displayName = profile?.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Anthropic OAuth"
        return Account(
            accountId: fallbackId,
            email: "",
            displayName: displayName,
            createdAt: Date()
        )
    }

    /// Fetches the OAuth profile (email + display name) for the given
    /// access token. Returns `nil` on any failure (network, non-200 HTTP,
    /// decode error) so the caller can fall back to a synthetic id; the
    /// failure mode is logged via `DevLog.trace`.
    ///
    /// Rationale: this replaces the previous `~/.claude.json` lookup. The
    /// CLI state file is outside the app's bookmark scope, so the OAuth
    /// profile endpoint is the only sandbox-safe source for the email.
    /// The endpoint URL follows the spec referenced in
    /// `https://github.com/anthropics/claude-code/issues/29666`.
    private func fetchOAuthProfile(accessToken: String) async -> OAuthProfile? {
        guard let url = URL(string: "https://api.anthropic.com/api/oauth/profile") else {
            return nil
        }
        DevLog.trace("AuthTrace", "fetchOAuthProfile starting url=\(url.absoluteString)")
        do {
            let (data, http) = try await makeAuthenticatedRequest(token: accessToken, for: url)
            DevLog.trace(
                "AuthTrace",
                "fetchOAuthProfile response status=\(http.statusCode) bytes=\(data.count)"
            )
            guard http.statusCode == 200 else {
                DevLog.trace(
                    "AuthTrace",
                    "OAuth profile fetch returned non-200 status=\(http.statusCode); falling back to synthetic accountId."
                )
                return nil
            }
            let profile = try JSONDecoder().decode(OAuthProfile.self, from: data)
            DevLog.trace(
                "AuthTrace",
                "fetchOAuthProfile decoded hasEmail=\(profile.email?.isEmpty == false) hasName=\(profile.name?.isEmpty == false)"
            )
            return profile
        } catch {
            DevLog.trace(
                "AuthTrace",
                "OAuth profile fetch failed error=\(error); falling back to synthetic accountId."
            )
            return nil
        }
    }

    private func clearPendingOAuth() {
        codeVerifier = nil
        pendingOAuthState = nil
        authState.isAwaitingCode = false
    }

    // MARK: - Token Exchange

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String
        let expires_in: Int?
    }

    private func exchangeCode(
        _ code: String, verifier: String, state: String
    ) async throws -> (accessToken: String, refreshToken: String, expiresAt: Date) {
        var request = URLRequest(url: URL(string: OAuth.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "client_id": OAuth.clientID,
            "redirect_uri": OAuth.redirectURI,
            "code_verifier": verifier,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw MacAuthError.tokenExchangeFailed
        }
        let tokens = try JSONDecoder().decode(TokenResponse.self, from: data)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expires_in ?? 3600))
        return (tokens.access_token, tokens.refresh_token, expiresAt)
    }

    // MARK: - Auto-Restore

    /// Attempts to restore an authenticated session from Tempo-owned
    /// per-account Keychain slots. If `registry.activeAccountId` points at
    /// a known account, that account is restored (refreshing on expiry).
    /// Otherwise the first known account with already-valid credentials is
    /// picked and promoted to active.
    ///
    /// The legacy Claude Code CLI Keychain path is intentionally opt-in:
    /// only the explicit "Use existing Claude Code CLI session" UI passes
    /// `includeCLIFallback = true`, because reading that item can display a
    /// macOS Keychain authorization prompt.
    func tryRestoreSession(includeCLIFallback: Bool = false) async -> Bool {
        // Prefer registry ordering; fall back to whatever the Keychain
        // enumerates (covers edge cases where the registry is empty but
        // credentials still exist on disk).
        let candidateIds: [String] = {
            if !registry.accounts.isEmpty {
                return registry.accounts.map { $0.accountId }
            }
            return CredentialStore.knownAccountIds()
        }()

        if let activeId = registry.activeAccountId, candidateIds.contains(activeId) {
            if await restoreAccount(accountId: activeId, allowRefresh: true) {
                return true
            }
            // Fall through to the CLI fallback below; do NOT silently promote
            // a different account when the user had explicitly selected one.
        } else {
            // No active account: pick the first candidate with VALID
            // credentials and promote it to active. Never refresh solely to
            // elect an account here.
            for accountId in candidateIds {
                if await restoreAccount(accountId: accountId, allowRefresh: false) {
                    return true
                }
            }
        }

        guard includeCLIFallback else {
            authState.isAuthenticated = false
            authState.authSource = .none
            assertInvariantIsAuthenticatedImpliesNonEmptyRegistry()
            return false
        }

        // Explicit fallback: legacy Claude Code CLI session. When the
        // user chooses this path and has valid CLI credentials, we
        // materialize a synthetic registry entry seeded by the CLI's
        // refresh token. The CLI's email is intentionally NOT looked up:
        // the only allowed scope is `~/.claude/`, which does not include
        // `~/.claude.json`.
        //
        // The registry entry carries only non-secret metadata (email,
        // displayName, accountId). The CLI tokens themselves stay in the
        // Claude Code keychain and are read via
        // `ClaudeCodeKeychainReader` on demand; this function never
        // refreshes, rotates, or writes them per `docs/AUTH_FLOW.md`.
        //
        // Invariant: after this branch returns,
        // `authState.isAuthenticated == true` implies
        // `registry.accounts.count >= 1`. The registration below is what
        // keeps that invariant intact after explicit CLI sign-in.
        if let cliTokens = ClaudeCodeKeychainReader.loadTokens(allowUserInteraction: true),
           !cliTokens.accessToken.isEmpty {
            guard ClaudeCodeKeychainReader.isAccessTokenFresh(cliTokens) else {
                DevLog.trace(
                    "AuthTrace",
                    "Claude Code CLI access token is expired; requiring Tempo OAuth instead of refreshing CLI credentials"
                )
                authState.isAuthenticated = false
                authState.authSource = .none
                assertInvariantIsAuthenticatedImpliesNonEmptyRegistry()
                return false
            }

            // CLI sessions cannot reliably identify the user. Reading the
            // CLI profile from `~/.claude.json` is unsupported under App
            // Sandbox (the file lives outside the granted bookmark scope),
            // so the email is intentionally NOT looked up here. The CLI
            // path always materializes a deterministic `cli-local-<hash>`
            // id seeded by the refresh token so re-launches with the same
            // CLI session produce the same accountId. A later Tempo OAuth
            // sign-in is responsible for promoting this synthetic entry
            // to a canonical email-backed id (see the migration in
            // `submitOAuthCode`).
            let refresh = cliTokens.refreshToken ?? ""
            let seed = refresh.isEmpty ? cliTokens.accessToken : refresh
            let canonicalId = AccountIdentifier.cliFallbackAccountId(from: seed)
            let displayName = "Claude Code (CLI)"

            if !registry.accounts.contains(where: { $0.accountId == canonicalId }) {
                let synthetic = Account(
                    accountId: canonicalId,
                    email: "",
                    displayName: displayName,
                    createdAt: Date()
                )
                registry.add(synthetic)
                DevLog.trace(
                    "AuthTrace",
                    "Registered CLI-backed account in registry accountId=\(canonicalId) source=cliSession emailBacked=false"
                )
            }

            if registry.activeAccountId != canonicalId {
                registry.setActive(accountId: canonicalId)
            }

            authState.isAuthenticated = true
            authState.authSource = .cliSession
            authState.requiresExplicitSignIn = false
            authState.accountEmail = displayName
            DevLog.trace(
                "AuthTrace",
                "Restored authenticated state from fresh CLI session accountId=\(canonicalId)"
            )
            assertInvariantIsAuthenticatedImpliesNonEmptyRegistry()
            return true
        }

        authState.isAuthenticated = false
        authState.authSource = .none
        assertInvariantIsAuthenticatedImpliesNonEmptyRegistry()
        return false
    }

    /// DEBUG-only regression canary for the
    /// invariant:
    ///
    ///     authState.isAuthenticated == true implies
    ///     AccountRegistry.accounts.count >= 1
    ///
    /// Silent no-op in release builds. If this assertion ever fires it
    /// means a new code path has reintroduced the half-signed-in state
    /// that caused the popover to render "Not signed in" together with
    /// "Fetching usage..." and a Logout row.
    private func assertInvariantIsAuthenticatedImpliesNonEmptyRegistry() {
        #if DEBUG
        if authState.isAuthenticated && registry.accounts.isEmpty {
            assertionFailure(
                "isAuthenticated with empty registry"
            )
        }
        #endif
    }

    /// Attempts to restore a single account. Returns true if the session was
    /// restored (either credentials were valid or a refresh succeeded) and
    /// `authState` was updated accordingly. Returns false otherwise and
    /// leaves `authState` untouched so the caller can try another candidate.
    private func restoreAccount(accountId: String, allowRefresh: Bool) async -> Bool {
        guard let credentials = CredentialStore.load(for: accountId) else { return false }

        if CredentialStore.isValid(credentials) {
            if registry.activeAccountId != accountId {
                registry.setActive(accountId: accountId)
            }
            syncAccountEmail(for: accountId)
            authState.isAuthenticated = true
            authState.authSource = .webOAuth
            authState.requiresExplicitSignIn = false
            DevLog.trace(
                "AuthTrace",
                "Restored authenticated state from valid web OAuth credentials accountId=\(accountId) expiresAt=\(credentials.expiresAt)"
            )
            scheduleOAuthProfileRefresh(for: accountId)
            return true
        }

        guard allowRefresh else { return false }

        do {
            _ = try await refreshAccessToken(for: accountId)
            if registry.activeAccountId != accountId {
                registry.setActive(accountId: accountId)
            }
            syncAccountEmail(for: accountId)
            authState.isAuthenticated = true
            authState.authSource = .webOAuth
            authState.requiresExplicitSignIn = false
            DevLog.trace(
                "AuthTrace",
                "Restored authenticated state after refreshing web OAuth credentials accountId=\(accountId)"
            )
            scheduleOAuthProfileRefresh(for: accountId)
            return true
        } catch {
            DevLog.trace(
                "AuthTrace",
                "Failed to restore web OAuth credentials accountId=\(accountId) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    /// Refreshes the cached email + displayName for an OAuth-restored
    /// account by hitting the profile endpoint in the background. Runs
    /// only on the OAuth restore path; the CLI fallback in
    /// `tryRestoreSession` deliberately does NOT call this because
    /// CLI sessions cannot be associated with an Anthropic account from
    /// inside the granted bookmark scope.
    ///
    /// On success the existing `Account` row is rewritten with the
    /// server-side email and displayName but the `accountId` is left
    /// untouched: changing the id mid-session would orphan the Keychain
    /// slot and the per-account iCloud directory. A subsequent OAuth
    /// sign-in (`submitOAuthCode`) is the only path that promotes a
    /// `cli-local-<hash>` entry to a canonical email-backed id.
    private func scheduleOAuthProfileRefresh(for accountId: String) {
        Task { [weak self] in
            await self?.refreshOAuthProfile(for: accountId)
        }
    }

    private func refreshOAuthProfile(for accountId: String) async {
        guard let credentials = CredentialStore.load(for: accountId),
              CredentialStore.isValid(credentials) else {
            return
        }
        guard let profile = await fetchOAuthProfile(accessToken: credentials.accessToken) else {
            return
        }
        guard let existing = registry.accounts.first(where: { $0.accountId == accountId }) else {
            return
        }
        let newEmail = profile.email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let newDisplayName: String = {
            if let name = profile.name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                return name
            }
            if !newEmail.isEmpty { return newEmail }
            return existing.displayName
        }()
        if existing.email == newEmail, existing.displayName == newDisplayName {
            return
        }
        let updated = Account(
            accountId: existing.accountId,
            email: newEmail,
            displayName: newDisplayName,
            createdAt: existing.createdAt
        )
        registry.add(updated)
        syncAccountEmail(for: accountId)
        DevLog.trace(
            "AuthTrace",
            "Refreshed OAuth profile metadata accountId=\(accountId) hasEmail=\(!newEmail.isEmpty)"
        )
    }

    // MARK: - Token Refresh

    /// Refreshes the OAuth access token for a specific `accountId`.
    ///
    /// Guardrails (see AGENTS.md):
    /// - Rewrites ONLY that accountId's Tempo Keychain slot
    ///   (`CredentialStore.save(_:for: accountId)`). It MUST NEVER touch
    ///   the Claude Code CLI Keychain slot (service
    ///   `"Claude Code-credentials"`), which remains owned by the
    ///   `claude` CLI. `ClaudeCodeKeychainReader` is a read-only reader
    ///   and exposes no write API on purpose.
    /// - Reads the current refresh token from this account's slot only.
    /// - Concurrent callers for the same accountId coalesce into one
    ///   in-flight request; refreshes for different accountIds run
    ///   independently so one worker's refresh cannot block or clobber
    ///   another's.
    func refreshAccessToken(for accountId: String) async throws -> String {
        if let inFlight = inFlightWebRefresh[accountId] {
            DevLog.trace(
                "AuthTrace",
                "Awaiting in-flight web OAuth refresh accountId=\(accountId)"
            )
            return try await inFlight.value
        }
        let task = Task<String, Error> { [weak self] in
            guard let self else { throw MacAuthError.noToken }
            return try await self.performWebRefresh(for: accountId)
        }
        inFlightWebRefresh[accountId] = task
        defer { inFlightWebRefresh.removeValue(forKey: accountId) }
        return try await task.value
    }

    private func performWebRefresh(for accountId: String) async throws -> String {
        #if DEBUG
        assert(!accountId.isEmpty, "accountId must be non-empty")
        assert(accountId != "__registry__", "Must not refresh tokens for the registry slot")
        #endif
        guard let credentials = CredentialStore.load(for: accountId),
              !credentials.refreshToken.isEmpty else {
            DevLog.trace(
                "AuthTrace",
                "Cannot refresh web OAuth token because no refresh token is stored accountId=\(accountId)"
            )
            signOut(for: accountId)
            throw MacAuthError.noToken
        }
        var request = URLRequest(url: URL(string: OAuth.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode([
            "grant_type": "refresh_token",
            "refresh_token": credentials.refreshToken,
            "client_id": OAuth.clientID,
            "scope": OAuth.scopes,
        ])
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode == 400 || statusCode == 401 {
            struct ErrorBody: Decodable { let error: String? }
            let body = try? JSONDecoder().decode(ErrorBody.self, from: data)
            if body?.error == "invalid_grant" || statusCode == 401 {
                DevLog.trace(
                    "AuthTrace",
                    "Web OAuth refresh failed accountId=\(accountId) status=\(statusCode) error=\(body?.error ?? "unknown")"
                )
                signOut(for: accountId)
                throw MacAuthError.refreshFailed
            }
        }
        guard statusCode == 200 else {
            DevLog.trace(
                "AuthTrace",
                "Web OAuth refresh failed accountId=\(accountId) status=\(statusCode)"
            )
            throw MacAuthError.httpError(statusCode)
        }
        struct RefreshResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Int?
        }
        let tokens = try JSONDecoder().decode(RefreshResponse.self, from: data)
        var updated = credentials
        updated.accessToken = tokens.access_token
        if let refreshToken = tokens.refresh_token, !refreshToken.isEmpty {
            updated.refreshToken = refreshToken
        }
        updated.expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expires_in ?? 3600))
        try? CredentialStore.save(updated, for: accountId)
        DevLog.trace(
            "AuthTrace",
            "Web OAuth refresh succeeded accountId=\(accountId) expiresAt=\(updated.expiresAt)"
        )
        return tokens.access_token
    }

    // MARK: - Authenticated Requests

    /// Performs an authenticated GET against the given `url` for a specific
    /// `accountId`. Uses that account's Keychain slot; on 401, refreshes
    /// ONLY that account's tokens and retries once. Falls back to the
    /// legacy Claude Code CLI session path only when the current auth
    /// source was established by the explicit CLI sign-in action.
    func authenticatedRequest(for url: URL, accountId: String) async throws -> Data {
        if let credentials = CredentialStore.load(for: accountId),
           !credentials.accessToken.isEmpty {
            return try await authenticatedRequestWithWebCredentials(
                credentials,
                for: url,
                accountId: accountId
            )
        }

        let canUseCLISession = authState.authSource == .cliSession || accountId.hasPrefix("cli-local-")
        guard canUseCLISession else {
            DevLog.trace(
                "AuthTrace",
                "Authenticated request skipped CLI fallback for non-CLI accountId=\(accountId)"
            )
            throw MacAuthError.noToken
        }

        // Fallback: Claude Code CLI session tokens (read-only).
        //
        // GUARDRAIL: this branch MUST NEVER write to the Claude Code CLI
        // Keychain slot (service `"Claude Code-credentials"`). The CLI
        // slot is owned by the `claude` CLI process, and Tempo is strictly
        // a reader via `ClaudeCodeKeychainReader`. On 401 we surface the
        // error to the caller instead of refreshing; clobbering the CLI
        // slot would break the user's `claude` login. See AGENTS.md
        // ("Keychain is the only home" / per-account guardrails).
        if let cliTokens = ClaudeCodeKeychainReader.loadTokens(allowUserInteraction: false),
           !cliTokens.accessToken.isEmpty {
            do {
                return try await authenticatedRequestWithCLITokens(cliTokens, for: url)
            } catch MacAuthError.refreshFailed {
                DevLog.trace("AuthTrace", "CLI token refresh failed; no web OAuth slot for accountId=\(accountId)")
            } catch MacAuthError.noToken {
                DevLog.trace("AuthTrace", "CLI token unavailable; no web OAuth slot for accountId=\(accountId)")
            } catch MacAuthError.httpError(401) {
                DevLog.trace("AuthTrace", "CLI token request returned 401; no web OAuth slot for accountId=\(accountId)")
            } catch {
                throw error
            }
        }

        DevLog.trace(
            "AuthTrace",
            "Authenticated request failed because no usable token source exists accountId=\(accountId)"
        )
        throw MacAuthError.noToken
    }

    private func handleAuthenticatedResponse(
        _ data: Data,
        _ http: HTTPURLResponse,
        source: TokenSource
    ) throws -> Data {
        switch http.statusCode {
        case 200:
            DevLog.trace("AuthTrace", "Authenticated request succeeded source=\(source.rawValue)")
            return data
        case 401:
            DevLog.trace("AuthTrace", "Authenticated request returned 401 source=\(source.rawValue)")
            throw MacAuthError.httpError(401)
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            let retryAfterLabel = retryAfter.map { String($0) } ?? "nil"
            DevLog.trace("AuthTrace", "Authenticated request rate limited source=\(source.rawValue) retryAfter=\(retryAfterLabel)")
            throw MacAuthError.rateLimited(retryAfter: retryAfter)
        default:
            DevLog.trace("AuthTrace", "Authenticated request failed source=\(source.rawValue) status=\(http.statusCode)")
            throw MacAuthError.httpError(http.statusCode)
        }
    }

    private func makeAuthenticatedRequest(token: String, for url: URL) async throws -> (Data, HTTPURLResponse) {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(API.betaHeader, forHTTPHeaderField: "anthropic-beta")
        let (data, response) = try await URLSession.shared.data(for: req)
        return (data, response as! HTTPURLResponse)
    }

    private func authenticatedRequestWithCLITokens(
        _ cliTokens: ClaudeCodeKeychainReader.CLITokens,
        for url: URL
    ) async throws -> Data {
        if let expiresAt = cliTokens.expiresAt {
            let expiryDate = Date(timeIntervalSince1970: expiresAt / 1000.0)
            if expiryDate <= Date().addingTimeInterval(60) {
                DevLog.trace("AuthTrace", "CLI access token appears expired; validating it before refresh")
            }
        }

        do {
            let (data, http) = try await makeAuthenticatedRequest(token: cliTokens.accessToken, for: url)
            return try handleAuthenticatedResponse(data, http, source: .cliSession)
        } catch MacAuthError.httpError(401) {
            DevLog.trace("AuthTrace", "CLI token returned 401; not refreshing Claude Code credentials")
            throw MacAuthError.httpError(401)
        }
    }

    private func authenticatedRequestWithWebCredentials(
        _ credentials: StoredCredentials,
        for url: URL,
        accountId: String
    ) async throws -> Data {
        do {
            let (data, http) = try await makeAuthenticatedRequest(token: credentials.accessToken, for: url)
            return try handleAuthenticatedResponse(data, http, source: .webOAuth)
        } catch MacAuthError.httpError(401) {
            DevLog.trace(
                "AuthTrace",
                "Web OAuth token returned 401; refreshing and retrying once accountId=\(accountId)"
            )
            let refreshedToken = try await refreshAccessToken(for: accountId)
            let (data, http) = try await makeAuthenticatedRequest(token: refreshedToken, for: url)
            return try handleAuthenticatedResponse(data, http, source: .webOAuth)
        }
    }

    // MARK: - Sign Out

    /// Signs out a specific account and reconciles `registry` + `authState`.
    /// Prefers the injected `removalService` for full cleanup (Keychain +
    /// iCloud directory + registry + mirror); falls back to a minimal
    /// `CredentialStore.delete` + `registry.remove` pair when no removal
    /// service was injected.
    func signOut(for accountId: String) {
        if let removalService {
            removalService.removeAccount(accountId: accountId)
        } else {
            do {
                try CredentialStore.delete(for: accountId)
            } catch {
                DevLog.trace(
                    "AuthTrace",
                    "Sign-out CredentialStore.delete failed accountId=\(accountId) error=\(error.localizedDescription)"
                )
            }
            registry.remove(accountId: accountId)
        }

        // Registry clears `activeAccountId` when the active one was removed.
        // Promote the first remaining account (if any) so there is always at
        // most one active account selected while any account exists.
        if registry.activeAccountId == nil {
            registry.setActive(accountId: registry.accounts.first?.accountId)
        }

        let stillAuthenticated = !registry.accounts.isEmpty
        authState.isAuthenticated = stillAuthenticated
        authState.isAwaitingCode = false
        authState.requiresExplicitSignIn = !stillAuthenticated
        authState.authSource = stillAuthenticated ? .webOAuth : .none
        if let activeId = registry.activeAccountId {
            syncAccountEmail(for: activeId)
        } else {
            authState.accountEmail = nil
        }

        // Forget any in-flight refresh for this account so a subsequent
        // re-sign-in does not coalesce onto the now-invalid task.
        inFlightWebRefresh.removeValue(forKey: accountId)

        DevLog.trace(
            "AuthTrace",
            "Signed out accountId=\(accountId) remaining=\(registry.accounts.count)"
        )
        onSignOut?(accountId)
    }

    // MARK: - Helpers

    /// Copies the given account's email into `authState.accountEmail` so the
    /// existing single-email UI surfaces the active account. Falls back to
    /// the display name when the account has no email (synthetic CLI id).
    private func syncAccountEmail(for accountId: String) {
        guard let account = registry.accounts.first(where: { $0.accountId == accountId }) else {
            authState.accountEmail = nil
            return
        }
        authState.accountEmail = account.email.isEmpty ? account.displayName : account.email
    }
}
