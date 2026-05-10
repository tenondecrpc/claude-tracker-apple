import Foundation

// MARK: - AccountRegistryICloudMirror
//
// Mirrors the non-secret account metadata held by `AccountRegistry` into the
// iCloud `Tempo/accounts/` tree so iOS can discover known accounts.
//
// The mirror writes two kinds of files:
//
//   Tempo/accounts/<percentEncodedAccountId>/account.json
//       Per-account metadata: accountId, email, displayName, createdAt.
//
//   Tempo/accounts/index.json
//       Ordered list of accountIds in the same order the registry exposes
//       them, plus a timestamp, so iOS can enumerate accounts without
//       scanning the directory.
//
// The mirror is intentionally best-effort: when no iCloud ubiquity container
// is available (iCloud signed out, entitlement missing, ...) helper URLs
// return `nil` and the mirror writes nothing. It traces via `DevLog` instead
// of throwing because callers treat this as a secondary sync path, not a
// critical persistence layer.
//
// Security guarantee: this type encodes `Account` values directly. `Account`
// holds only non-secret fields. This type MUST NEVER serialize or touch
// credential material (see `CredentialStore`, `StoredCredentials`). Do not
// extend the payload with token or refresh-token fields.
//
// Scope of this type is intentionally narrow. It knows about
// `Tempo/accounts/<id>/account.json` and `Tempo/accounts/index.json` only.
// Full per-account directory removal (including `usage.json`,
// `usage-history.json`, `latest.json`) is handled by task 2.5 in a different
// component.
//
// Wiring: this type is NOT yet owned by `MacAppCoordinator`. Task 3.6 is
// responsible for constructing the mirror alongside `AccountRegistry` and
// invoking `writeMirror(for:)` after registry mutations plus
// `deleteMetadata(for:)` when an account is removed.
@MainActor
final class AccountRegistryICloudMirror {

    // MARK: Init

    init() {}

    // MARK: Write API

    /// Writes the full set of per-account `account.json` files plus the
    /// shared `index.json`, derived from the current state of `registry`.
    ///
    /// The call is idempotent: running it repeatedly with the same registry
    /// state produces the same iCloud bytes. Directories are created as
    /// needed with `withIntermediateDirectories: true`. Failures on any
    /// single per-account file do not abort the rest of the pass; each
    /// issue is traced via `DevLog` and the mirror continues so the index
    /// still reflects the registry.
    ///
    /// Note: stale per-account `account.json` files for accounts that have
    /// since been removed are NOT swept here. Callers that remove an
    /// account should invoke `deleteMetadata(for:)` to clean up the stale
    /// metadata file, then call `writeMirror(for:)` again to refresh the
    /// index.
    func writeMirror(for registry: AccountRegistry) {
        let accounts = registry.accounts

        for account in accounts {
            writeAccountMetadata(account)
        }

        writeIndex(accountIds: accounts.map { $0.accountId })
    }

    /// Deletes the per-account `account.json` metadata file for the given
    /// accountId. Does NOT delete the enclosing directory or any other
    /// per-account files (`usage.json`, `usage-history.json`,
    /// `latest.json`); that broader cleanup is task 2.5.
    ///
    /// Callers should typically invoke `writeMirror(for:)` after this to
    /// refresh `index.json` so the removed accountId is dropped from the
    /// list.
    func deleteMetadata(for accountId: String) {
        guard let fileURL = TempoICloud.accountMetadataFileURL(for: accountId) else {
            DevLog.trace(
                "AccountMirror",
                "deleteMetadata skipped because iCloud container is unavailable accountId=\(accountId)"
            )
            return
        }

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            DevLog.trace(
                "AccountMirror",
                "deleteMetadata no-op because file is absent path=\(fileURL.path)"
            )
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
            DevLog.trace(
                "AccountMirror",
                "deleteMetadata removed file path=\(fileURL.path)"
            )
        } catch {
            DevLog.trace(
                "AccountMirror",
                "deleteMetadata failed to remove file path=\(fileURL.path) error=\(error.localizedDescription)"
            )
        }
    }

    // MARK: Private writers

    private func writeAccountMetadata(_ account: Account) {
        guard let fileURL = TempoICloud.accountMetadataFileURL(for: account.accountId) else {
            DevLog.trace(
                "AccountMirror",
                "writeAccountMetadata skipped because iCloud container is unavailable accountId=\(account.accountId)"
            )
            return
        }

        let directoryURL = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(account)
            try data.write(to: fileURL, options: .atomic)

            DevLog.trace(
                "AccountMirror",
                "writeAccountMetadata wrote file path=\(fileURL.path) accountId=\(account.accountId)"
            )
        } catch {
            DevLog.trace(
                "AccountMirror",
                "writeAccountMetadata failed path=\(fileURL.path) accountId=\(account.accountId) error=\(error.localizedDescription)"
            )
        }
    }

    private func writeIndex(accountIds: [String]) {
        guard
            let indexURL = TempoICloud.indexFileURL(),
            let accountsDirURL = TempoICloud.accountsDirectoryURL()
        else {
            DevLog.trace(
                "AccountMirror",
                "writeIndex skipped because iCloud container is unavailable count=\(accountIds.count)"
            )
            return
        }

        // Empty-write guard (cli-session-registry-consistency-fix,
        // Property 2): avoid thrashing `Tempo/accounts/index.json` with
        // successive `count=0` writes during boot on a CLI-only machine
        // where the caller-side seed was mistakenly invoked. Intentional
        // last-account clears (invoked from `AccountRemovalService` after
        // removing the final account) still write through because the
        // remote index had `count >= 1` before the write.
        //
        // Four cases when `accountIds.isEmpty`:
        //   (a) Remote file absent        -> no-op
        //   (b) Remote `count == 0`       -> no-op
        //   (c) Remote `count >= 1`       -> write through (intentional clear)
        //   (d) Remote present but corrupt/undecodable -> write through
        //       (conservative: cannot confirm remote state)
        if accountIds.isEmpty {
            let fileManager = FileManager.default
            if !fileManager.fileExists(atPath: indexURL.path) {
                DevLog.trace(
                    "AccountMirror",
                    "writeIndex no-op because registry empty and remote index is absent path=\(indexURL.path)"
                )
                return
            }

            if let remoteData = try? Data(contentsOf: indexURL) {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let remoteIndex = try? decoder.decode(AccountsIndexFile.self, from: remoteData),
                   remoteIndex.accountIds.isEmpty {
                    DevLog.trace(
                        "AccountMirror",
                        "writeIndex no-op because registry empty and remote index is already count=0 path=\(indexURL.path)"
                    )
                    return
                }
                // Fall through: remote has count >= 1 (intentional clear)
                // or is undecodable (conservative write).
            }
            // Fall through: remote is unreadable for some other reason;
            // conservative single write is acceptable.
        }

        let payload = AccountsIndexFile(accountIds: accountIds, updatedAt: Date())

        do {
            try FileManager.default.createDirectory(
                at: accountsDirURL,
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try data.write(to: indexURL, options: .atomic)

            DevLog.trace(
                "AccountMirror",
                "writeIndex wrote file path=\(indexURL.path) count=\(accountIds.count)"
            )
        } catch {
            DevLog.trace(
                "AccountMirror",
                "writeIndex failed path=\(indexURL.path) count=\(accountIds.count) error=\(error.localizedDescription)"
            )
        }
    }
}

// MARK: - AccountsIndex
//
// `Tempo/accounts/index.json` uses the shared wire type
// `AccountsIndexFile` (see `Shared/AccountsIndexFile.swift`). iOS readers
// and widget code decode the same type directly.
