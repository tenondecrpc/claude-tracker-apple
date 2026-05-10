import Foundation

/// A known Anthropic account tracked by Tempo.
///
/// `accountId` is the canonical identifier used across Keychain slots, iCloud
/// paths, widget snapshots, and WatchConnectivity payloads. Canonicalization
/// (email normalization, fallback id generation) is handled by a dedicated
/// helper type; this model stores `accountId` as-is.
struct Account: Codable, Identifiable, Equatable {
    let accountId: String
    let email: String
    let displayName: String
    let createdAt: Date

    var id: String { accountId }

    init(
        accountId: String,
        email: String,
        displayName: String,
        createdAt: Date
    ) {
        self.accountId = accountId
        self.email = email
        self.displayName = displayName
        self.createdAt = createdAt
    }

    // Equality is intentionally accountId-only so that renames (displayName) or
    // profile email-case changes do not create spurious inequality between two
    // references to the same logical account.
    static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.accountId == rhs.accountId
    }
}
