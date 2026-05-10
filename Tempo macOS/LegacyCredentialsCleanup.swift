import Foundation
import Security

// MARK: - LegacyCredentialsCleanup
//
// One-shot startup sweep that removes the two artifacts from the pre-multi-
// account single-slot credential layout:
//
//   1. A Keychain item under service `com.tenondev.tempo.claude.oauth` with
//      `kSecAttrAccount = "credentials"` (the old fixed slot).
//   2. The on-disk file `~/.config/tempo-for-claude/credentials.json` (the
//      even-older file-based store, prior to the Keychain migration).
//
// The sweep deletes both artifacts unconditionally. It never reads their
// contents and never throws. A `UserDefaults` flag records that a sweep has
// been attempted so subsequent launches early-return.
//
// Wiring into startup is the responsibility of `MacAppCoordinator` (see
// task 3.6). This file exposes only the utility.

enum LegacyCredentialsCleanup {

    /// `UserDefaults` key that records a sweep attempt. Once set to `true`,
    /// `sweep()` early-returns on all subsequent calls.
    static let userDefaultsFlagKey = "tempo.legacyCredentialsCleanupDone"

    private static let legacyKeychainService = "com.tenondev.tempo.claude.oauth"
    private static let legacyKeychainAccount = "credentials"

    private static let legacyFileRelativePath = ".config/tempo-for-claude/credentials.json"

    /// Delete the legacy Keychain slot and the legacy on-disk credentials
    /// file, if present. Safe to call on any actor; does not throw.
    /// Subsequent calls after the first are no-ops.
    static func sweep() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: userDefaultsFlagKey) { return }

        deleteLegacyKeychainSlot()
        deleteLegacyCredentialsFile()

        defaults.set(true, forKey: userDefaultsFlagKey)
    }

    // MARK: - Private

    private static func deleteLegacyKeychainSlot() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyKeychainService,
            kSecAttrAccount as String: legacyKeychainAccount
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            DevLog.trace(
                "AuthTrace",
                "LegacyCredentialsCleanup keychain delete failed status=\(status)"
            )
        }
    }

    private static func deleteLegacyCredentialsFile() {
        let fileURL = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent(legacyFileRelativePath)

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
                                        && error.code == NSFileNoSuchFileError {
            // Missing file is the expected common case; nothing to do.
        } catch CocoaError.fileNoSuchFile {
            // Also fine: no legacy file to remove.
        } catch {
            DevLog.trace(
                "AuthTrace",
                "LegacyCredentialsCleanup file delete failed path=\(fileURL.path) error=\(error.localizedDescription)"
            )
        }
    }
}
