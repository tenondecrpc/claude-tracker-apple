import Foundation
import CryptoKit

/// Errors produced while deriving a canonical `accountId` from an email or
/// other seed value.
nonisolated enum AccountIdentifierError: Error, Equatable {
    /// The provided email was empty (or contained only whitespace) after
    /// canonicalization. Canonical `accountId` values must be non-empty.
    case emptyEmail
}

/// Namespace for deriving the canonical `accountId` used across Keychain
/// slots, iCloud paths, widget snapshots, and WatchConnectivity payloads.
///
/// The `accountId` is the lowercased, trimmed, NFC-normalized email returned
/// by the Anthropic OAuth profile. The canonical form is reused verbatim for
/// Keychain `kSecAttrAccount` values and for iCloud directory names. Only the
/// directory name is percent-encoded for filesystem safety; the in-memory
/// `accountId` always stays canonical.
nonisolated enum AccountIdentifier {
    /// Sentinel `accountId` used for session-level payloads (`SessionInfo`,
    /// `LocalProjectStat`) whose owning account cannot be determined, for
    /// example CLI-only sessions whose `oauthAccount` does not match any
    /// known Anthropic account.
    ///
    /// This is used ONLY for session-scoped types that the design allows to
    /// land in an `"unassigned"` bucket. `UsageState` remains strict and does
    /// NOT fall back to this value on decoding.
    static let unassignedAccountId: String = "unassigned"

    /// Canonicalize an email into the stable `accountId` form.
    ///
    /// Steps:
    /// 1. NFC Unicode normalization (`precomposedStringWithCanonicalMapping`).
    /// 2. Trim leading and trailing whitespace and newlines.
    /// 3. Lowercase via Swift's Unicode-aware `lowercased()`.
    /// 4. Reject empty input with `AccountIdentifierError.emptyEmail`.
    ///
    /// - Parameter email: Raw email address from the OAuth profile or user
    ///   input.
    /// - Returns: Canonical `accountId`.
    /// - Throws: `AccountIdentifierError.emptyEmail` when the canonicalized
    ///   value is empty.
    static func canonicalize(email: String) throws -> String {
        let normalized = email
            .precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !normalized.isEmpty else {
            throw AccountIdentifierError.emptyEmail
        }

        return normalized
    }

    /// Synthesize a stable CLI-only fallback `accountId` for the rare case
    /// where the OAuth profile omits an email. The caller is expected to
    /// surface this as an "Unknown account" in the UI per design.md.
    ///
    /// The returned id is deterministic for a given `seed`, so re-deriving it
    /// from the same CLI profile produces the same `accountId`.
    ///
    /// - Parameter seed: Stable seed material, e.g. a CLI profile path or
    ///   opaque profile identifier. An empty seed is permitted; the hash will
    ///   still be stable (the SHA256 of the empty string).
    /// - Returns: A synthetic `accountId` of the form `"cli-local-<shortHash>"`,
    ///   where `<shortHash>` is the first 8 hex characters of SHA256(seed).
    static func cliFallbackAccountId(from seed: String) -> String {
        let digest = SHA256.hash(data: Data(seed.utf8))
        let hexPrefix = digest
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
        return "cli-local-\(hexPrefix)"
    }

    /// Percent-encode a canonical `accountId` for use as an iCloud directory
    /// name. Any character outside `[a-z0-9._@-]` is percent-encoded so the
    /// name is safe across filesystems and iCloud metadata queries.
    ///
    /// This transformation is one-way for display: callers MUST keep the
    /// canonical `accountId` in memory and only use this form when building a
    /// filesystem path.
    ///
    /// - Parameter accountId: Canonical `accountId` (already lowercased and
    ///   NFC-normalized).
    /// - Returns: Percent-encoded directory-safe form.
    static func percentEncodedDirectoryName(for accountId: String) -> String {
        accountId
            .addingPercentEncoding(withAllowedCharacters: directoryNameAllowedCharacters)
            ?? accountId
    }

    /// Allowed character set for iCloud directory names: lowercase ASCII
    /// letters, digits, `.`, `_`, `@`, and `-`. Anything else is percent-
    /// encoded by `percentEncodedDirectoryName(for:)`.
    private static let directoryNameAllowedCharacters: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "abcdefghijklmnopqrstuvwxyz")
        set.insert(charactersIn: "0123456789")
        set.insert(charactersIn: "._@-")
        return set
    }()
}
