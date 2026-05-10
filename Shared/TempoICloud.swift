import Foundation

enum TempoICloud {
    nonisolated static let containerIdentifier = "iCloud.com.tenondev.tempo.claude"

    // MARK: - Per-account helpers
    //
    // These helpers build URLs under `Tempo/accounts/` for the multi-account
    // layout described in `openspec/changes/multi-account-support/design.md`.
    //
    // Tree:
    // ```
    // Tempo/
    //   accounts/
    //     index.json                       <- indexFileURL()
    //     <accountIdDir>/
    //       account.json                   <- accountMetadataFileURL(for:)
    //       usage.json                     <- usageFileURL(for:)
    //       usage-history.json             <- usageHistoryFileURL(for:)
    //       latest.json                    <- latestSessionFileURL(for:)
    // ```
    //
    // `<accountIdDir>` is produced by
    // `AccountIdentifier.percentEncodedDirectoryName(for:)` so the filesystem
    // form is safe while the in-memory `accountId` stays canonical.
    //
    // All helpers return `nil` when no iCloud ubiquity container is available
    // (for example, iCloud is signed out or the entitlement is missing).
    // Callers that need a local fallback should resolve it at the call site
    // and not extend these helpers.

    /// Resolves the `Documents/Tempo/` root inside the iCloud ubiquity
    /// container. Returns `nil` when the container is unavailable.
    private static func tempoRootURL() -> URL? {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: containerIdentifier
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent("Documents/Tempo", isDirectory: true)
    }

    /// Returns the shared accounts directory (`<tempo>/accounts/`) that holds
    /// the per-account subdirectories and the `index.json` discovery file.
    static func accountsDirectoryURL() -> URL? {
        tempoRootURL()?.appendingPathComponent("accounts", isDirectory: true)
    }

    /// Returns the per-account directory
    /// (`<tempo>/accounts/<percentEncodedAccountId>/`).
    ///
    /// - Parameter accountId: Canonical `accountId` (as produced by
    ///   `AccountIdentifier.canonicalize(email:)`). Percent-encoding for
    ///   filesystem safety is applied here via
    ///   `AccountIdentifier.percentEncodedDirectoryName(for:)`.
    static func accountDirectoryURL(for accountId: String) -> URL? {
        guard let accountsDir = accountsDirectoryURL() else { return nil }
        let directoryName = AccountIdentifier.percentEncodedDirectoryName(for: accountId)
        return accountsDir.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Returns the shared `accounts/index.json` file that lists known
    /// `accountId`s for iOS discovery and widget intents.
    static func indexFileURL() -> URL? {
        accountsDirectoryURL()?.appendingPathComponent("index.json", isDirectory: false)
    }

    /// Returns `<accountDir>/account.json` - per-account non-secret metadata.
    static func accountMetadataFileURL(for accountId: String) -> URL? {
        accountDirectoryURL(for: accountId)?
            .appendingPathComponent("account.json", isDirectory: false)
    }

    /// Returns `<accountDir>/usage.json` - the current `UsageState` for the
    /// account.
    static func usageFileURL(for accountId: String) -> URL? {
        accountDirectoryURL(for: accountId)?
            .appendingPathComponent("usage.json", isDirectory: false)
    }

    /// Returns `<accountDir>/usage-history.json` - the per-account usage
    /// history.
    static func usageHistoryFileURL(for accountId: String) -> URL? {
        accountDirectoryURL(for: accountId)?
            .appendingPathComponent("usage-history.json", isDirectory: false)
    }

    /// Returns `<accountDir>/latest.json` - the latest relayed Claude Code
    /// session event for the account.
    static func latestSessionFileURL(for accountId: String) -> URL? {
        accountDirectoryURL(for: accountId)?
            .appendingPathComponent("latest.json", isDirectory: false)
    }
}
