import Foundation

// MARK: - AccountsIndexFile
//
// Wire format for `Tempo/accounts/index.json`, the shared discovery file
// that enumerates known Anthropic accounts for iOS readers and widget
// intents.
//
// The file is produced on macOS by `AccountRegistryICloudMirror` and
// consumed on iOS by `iCloudUsageReader`. Both sides use this same type so
// the on-disk shape stays in sync.
//
// Payload:
//
//   ```
//   {
//     "accountIds": ["alice@example.com", "bob@example.com"],
//     "updatedAt": "2025-03-10T18:30:00Z"
//   }
//   ```
//
// `accountIds` is kept in the same order the macOS `AccountRegistry` exposes
// accounts so that iOS can use position 0 as a sensible default when the
// user has not yet picked an active account (task 5.3).
//
// `accountIds` are canonical identifiers (see `AccountIdentifier`) - they
// are NOT percent-encoded. Percent-encoding is only applied when an
// `accountId` is used as a directory name via
// `AccountIdentifier.percentEncodedDirectoryName(for:)`.
nonisolated struct AccountsIndexFile: Codable, Equatable {
    let accountIds: [String]
    let updatedAt: Date
}
