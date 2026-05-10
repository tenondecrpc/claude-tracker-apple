import Foundation
import Security

// MARK: - ClaudeCodeKeychainReader

/// Reads OAuth tokens from the Claude Code CLI's macOS Keychain entry.
/// Service: "Claude Code-credentials", Account: $USER
///
/// Caches results in memory and suppresses repeat reads after the user denies
/// or cancels the keychain prompt, so a single denial does not turn into a
/// barrage of dialogs across the polling and request paths.
enum ClaudeCodeKeychainReader {

    private static let serviceName = "Claude Code-credentials"

    /// Successful CLI reads stay in memory for this app run. Tempo does
    /// not own the Claude Code Keychain slot, so avoiding repeated reads
    /// also avoids repeated macOS authorization prompts.
    private static let tokenCacheTTL: TimeInterval = 365 * 24 * 60 * 60

    /// Short cache for benign misses and non-interactive reads that cannot
    /// complete without UI.
    private static let missCacheTTL: TimeInterval = 30

    /// How long a user-denied or user-cancelled read suppresses retries.
    private static let denialBackoff: TimeInterval = 30 * 60

    struct CLITokens: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: TimeInterval?
        let scopes: [String]
        let subscriptionType: String?
        let clientId: String?
    }

    struct SecureStorageData: Codable {
        let claudeAiOauth: CLITokens?
    }

    private struct CacheEntry {
        let tokens: CLITokens?
        let storedAt: Date
        let ttl: TimeInterval

        var isFresh: Bool { Date().timeIntervalSince(storedAt) < ttl }
    }

    private static let cacheLock = NSLock()
    private static var cache: CacheEntry?

    /// Returns the CLI OAuth tokens if available in the macOS Keychain.
    static func loadTokens(allowUserInteraction: Bool = false) -> CLITokens? {
        DevLog.trace("KeychainTrace", "Claude Code credential token load requested")
        DevLog.trace("AuthTrace", "Claude Code keychain token load requested")
        if let cached = cachedEntry() {
            DevLog.trace("KeychainTrace", "Claude Code credential token load served from cache")
            DevLog.trace("AuthTrace", "Claude Code keychain token load served from in-memory cache")
            return cached.tokens
        }

        DevLog.trace("KeychainTrace", "Claude Code credential cache miss; querying Keychain")
        DevLog.trace("AuthTrace", "Claude Code keychain token cache miss; querying Security framework")
        let tokens = loadTokensWithSecurityFramework(allowUserInteraction: allowUserInteraction)
        return tokens
    }

    /// Drops the in-memory cache so the next call re-reads the keychain.
    /// Call this after a successful sign-in or when the user explicitly
    /// retries access from the UI.
    static func invalidateCache() {
        cacheLock.lock()
        cache = nil
        cacheLock.unlock()
    }

    private static func cachedEntry() -> CacheEntry? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        guard let entry = cache, entry.isFresh else { return nil }
        return entry
    }

    private static func storeCache(_ tokens: CLITokens?, ttl: TimeInterval) {
        cacheLock.lock()
        cache = CacheEntry(tokens: tokens, storedAt: Date(), ttl: ttl)
        cacheLock.unlock()
    }

    private static func loadTokensWithSecurityFramework(allowUserInteraction: Bool) -> CLITokens? {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceName,
            kSecAttrAccount: NSUserName(),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        query[kSecUseAuthenticationUI] = allowUserInteraction
            ? kSecUseAuthenticationUIAllow
            : kSecUseAuthenticationUIFail

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let tokens = decodeTokens(from: data) else {
                DevLog.trace("KeychainTrace", "Claude Code credential item read succeeded but decode failed")
                DevLog.trace("AuthTrace", "Claude Code keychain read returned data but decoding failed")
                storeCache(nil, ttl: missCacheTTL)
                return nil
            }
            DevLog.trace("KeychainTrace", "Claude Code credential item read succeeded")
            DevLog.trace("AuthTrace", "Loaded Claude Code CLI tokens via Security framework")
            storeCache(tokens, ttl: tokenCacheTTL)
            return tokens

        case errSecItemNotFound:
            DevLog.trace("KeychainTrace", "Claude Code credential item not found")
            DevLog.trace("AuthTrace", "Claude Code keychain item not found")
            storeCache(nil, ttl: missCacheTTL)
            return nil

        case errSecInteractionNotAllowed:
            DevLog.trace("KeychainTrace", "Claude Code credential item requires UI; non-interactive read skipped")
            DevLog.trace("AuthTrace", "Claude Code keychain read required UI and was skipped")
            storeCache(nil, ttl: missCacheTTL)
            return nil

        case errSecUserCanceled, errSecAuthFailed:
            DevLog.trace("KeychainTrace", "Claude Code credential item access denied or canceled status=\(status)")
            DevLog.trace(
                "AuthTrace",
                "Claude Code keychain access denied by user status=\(status); suppressing further reads for \(Int(denialBackoff))s"
            )
            storeCache(nil, ttl: denialBackoff)
            return nil

        default:
            DevLog.trace("KeychainTrace", "Claude Code credential item read failed status=\(status)")
            DevLog.trace("AuthTrace", "Claude Code keychain read failed status=\(status)")
            storeCache(nil, ttl: missCacheTTL)
            return nil
        }
    }

    private static func decodeTokens(from data: Data) -> CLITokens? {
        let jsonData: Data
        if let string = String(data: data, encoding: .utf8) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            jsonData = Data(trimmed.utf8)
        } else {
            jsonData = data
        }

        let storage = try? JSONDecoder().decode(SecureStorageData.self, from: jsonData)
        return storage?.claudeAiOauth
    }

    /// Returns true if valid CLI OAuth tokens exist in the keychain.
    static func hasValidSession() -> Bool {
        guard let tokens = loadTokens(), !tokens.accessToken.isEmpty else { return false }
        return isAccessTokenFresh(tokens)
    }

    /// Returns true when Claude Code has enough local state to restore without a web login.
    static func hasRestorableSession() -> Bool {
        guard let tokens = loadTokens() else { return false }
        return !tokens.accessToken.isEmpty
    }

    static func isAccessTokenFresh(_ tokens: CLITokens) -> Bool {
        if let expiresAt = tokens.expiresAt {
            let expiryDate = Date(timeIntervalSince1970: expiresAt / 1000.0)
            return expiryDate > Date().addingTimeInterval(60)
        }
        return true
    }
}
