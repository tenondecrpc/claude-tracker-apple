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

    init() {
        if let credentials = CredentialStore.load(), CredentialStore.isValid(credentials) {
            isAuthenticated = true
        }
        accountEmail = ClaudeCodeProfile.load()?.oauthAccount?.emailAddress
    }
}

// MARK: - ClaudeCodeProfile

private struct ClaudeCodeProfile: Decodable {
    struct OAuthAccount: Decodable {
        let emailAddress: String?
        let displayName: String?
    }
    let oauthAccount: OAuthAccount?

    static func load() -> ClaudeCodeProfile? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.claude.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(ClaudeCodeProfile.self, from: data)
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

    let authState: MacAuthState
    var onSignOut: (() -> Void)?

    private var codeVerifier: String?
    private var pendingOAuthState: String?

    init(authState: MacAuthState) {
        self.authState = authState
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

    // MARK: - Sign In (Task 2.1)

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

        if parts.count > 1 {
            guard parts[1] == pendingOAuthState else {
                clearPendingOAuth()
                throw MacAuthError.invalidCallback
            }
        }

        guard let verifier = codeVerifier else {
            clearPendingOAuth()
            throw MacAuthError.invalidCallback
        }

        let tokens = try await exchangeCode(code, verifier: verifier, state: pendingOAuthState ?? "")
        let credentials = StoredCredentials(
            accessToken: tokens.accessToken,
            refreshToken: tokens.refreshToken,
            expiresAt: tokens.expiresAt,
            scopes: OAuth.scopes.components(separatedBy: " ")
        )
        try CredentialStore.save(credentials)
        authState.isAuthenticated = true
        clearPendingOAuth()
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

    // MARK: - Auto-Restore (Task 2.3)

    /// Checks for valid stored credentials and restores the session. Returns true if authenticated.
    func tryRestoreSession() async -> Bool {
        guard let credentials = CredentialStore.load() else { return false }
        if CredentialStore.isValid(credentials) {
            authState.isAuthenticated = true
            return true
        }
        // Token expired - try refresh
        do {
            _ = try await refreshAccessToken()
            authState.isAuthenticated = true
            return true
        } catch {
            return false
        }
    }

    // MARK: - Token Refresh (Task 2.4)

    func refreshAccessToken() async throws -> String {
        guard let credentials = CredentialStore.load(), !credentials.refreshToken.isEmpty else {
            signOut()
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
                signOut()
                throw MacAuthError.refreshFailed
            }
        }
        guard statusCode == 200 else { throw MacAuthError.httpError(statusCode) }
        struct RefreshResponse: Decodable { let access_token: String; let expires_in: Int? }
        let tokens = try JSONDecoder().decode(RefreshResponse.self, from: data)
        var updated = credentials
        updated.accessToken = tokens.access_token
        updated.expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expires_in ?? 3600))
        try? CredentialStore.save(updated)
        return tokens.access_token
    }

    // MARK: - Authenticated Requests

    func authenticatedRequest(for url: URL) async throws -> Data {
        guard let credentials = CredentialStore.load(), !credentials.accessToken.isEmpty else {
            throw MacAuthError.noToken
        }
        var accessToken = credentials.accessToken

        func makeRequest(token: String) async throws -> (Data, HTTPURLResponse) {
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue(API.betaHeader, forHTTPHeaderField: "anthropic-beta")
            let (data, response) = try await URLSession.shared.data(for: req)
            return (data, response as! HTTPURLResponse)
        }

        var (data, http) = try await makeRequest(token: accessToken)

        if http.statusCode == 401 {
            accessToken = try await refreshAccessToken()
            (data, http) = try await makeRequest(token: accessToken)
        }

        switch http.statusCode {
        case 200:
            return data
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw MacAuthError.rateLimited(retryAfter: retryAfter)
        default:
            throw MacAuthError.httpError(http.statusCode)
        }
    }

    // MARK: - Sign Out (Task 2.5)

    func signOut() {
        authState.isAuthenticated = false
        authState.isAwaitingCode = false
        authState.requiresExplicitSignIn = true
        onSignOut?()
    }
}
