import Foundation

// MARK: - AccountRemovalService
//
// Orchestrates the full removal of an Anthropic account from the macOS app.
// Composes the three lower-level components that own different slices of
// account state:
//
// - `CredentialStore`: per-account OAuth Keychain slot.
// - `AccountRegistryICloudMirror`: iCloud `account.json` metadata and the
//   shared `accounts/index.json` discovery file.
// - `AccountRegistry`: in-memory/observable account list, active-account
//   pointer, and the `__registry__` Keychain slot that mirrors the list.
//
// Keeping this as a small orchestrator (rather than a method on
// `AccountRegistry` or the mirror) preserves the single-responsibility split
// established by tasks 2.1 through 2.3: the registry stays focused on
// in-memory/Keychain-metadata state and the mirror stays focused on iCloud
// JSON. Callers that need "remove this account and all its traces" get one
// entry point instead of manually sequencing four different APIs.
//
// Per `design.md` ("No retired copy"): this service does NOT move or archive
// per-account files before deletion. The per-account iCloud directory is
// removed outright via `FileManager.removeItem(at:)`.
//
// Wiring: this type is NOT yet wired into `MacAppCoordinator` or the
// Preferences UI. Tasks 3.6 and 4.3 are responsible for constructing this
// service alongside `AccountRegistry` + `AccountRegistryICloudMirror` and
// invoking `removeAccount(accountId:)` from the per-row sign-out action.
@MainActor
final class AccountRemovalService {

    // MARK: Dependencies

    private let registry: AccountRegistry
    private let mirror: AccountRegistryICloudMirror

    // MARK: Init

    init(registry: AccountRegistry, mirror: AccountRegistryICloudMirror) {
        self.registry = registry
        self.mirror = mirror
    }

    // MARK: Public API

    /// Removes an account and all of its locally- and iCloud-stored state
    /// in a fixed, idempotent order. Safe to call with an `accountId` that
    /// is unknown to the registry; each step below no-ops gracefully on
    /// missing artifacts so partial prior runs are recovered cleanly.
    ///
    /// Order:
    ///
    /// 1. Delete the per-account Keychain credential slot. Any failure is
    ///    traced via `DevLog` and ignored; a leftover Keychain slot is
    ///    recoverable on a future attempt and must not block iCloud cleanup.
    /// 2. Remove the per-account iCloud directory
    ///    (`Tempo/accounts/<percentEncodedAccountId>/`) and everything under
    ///    it (`usage.json`, `usage-history.json`, `latest.json`,
    ///    `account.json`). A missing directory is expected and ignored.
    ///    Other `removeItem(at:)` failures are traced and ignored so the
    ///    in-memory registry still gets cleaned up.
    /// 3. Delete the stale `account.json` metadata via
    ///    `mirror.deleteMetadata(for:)`. The enclosing directory was already
    ///    removed in step 2, but running this call keeps the mirror's
    ///    invariants explicit and is a no-op when the file is absent.
    /// 4. Call `registry.remove(accountId:)` to drop the account from the
    ///    observable `accounts` list, clear `activeAccountId` if it pointed
    ///    at the removed account, and persist the updated list to the
    ///    `__registry__` Keychain slot.
    /// 5. Call `mirror.writeMirror(for:)` to re-serialize
    ///    `accounts/index.json` so the removed `accountId` drops out of the
    ///    discovery list seen by iOS and widget intents.
    func removeAccount(accountId: String) {
        // Step 1: Keychain credentials.
        do {
            try CredentialStore.delete(for: accountId)
        } catch {
            DevLog.trace(
                "AccountRemoval",
                "CredentialStore.delete failed accountId=\(accountId) error=\(error.localizedDescription)"
            )
        }

        // Step 2: iCloud per-account directory.
        deleteAccountDirectory(accountId: accountId)

        // Step 3: iCloud metadata file (defensive; directory removal above
        // would already have taken it).
        mirror.deleteMetadata(for: accountId)

        // Step 4: In-memory registry + __registry__ Keychain slot.
        registry.remove(accountId: accountId)

        // Step 5: Refresh the iCloud index.
        mirror.writeMirror(for: registry)

        // Step 6: Remove the per-account widget snapshot from the App
        // Group container so widgets do not keep rendering the
        // signed-out account's data and the `SelectAccountIntent`
        // suggestion list does not surface a removed account. Clears
        // the active-account pointer too when it still references the
        // signed-out account.
        TempoWidgetSnapshotStore.delete(accountId: accountId, platform: .macOS)
    }

    // MARK: - Private

    private func deleteAccountDirectory(accountId: String) {
        guard let directoryURL = TempoICloud.accountDirectoryURL(for: accountId) else {
            DevLog.trace(
                "AccountRemoval",
                "deleteAccountDirectory skipped because iCloud container is unavailable accountId=\(accountId)"
            )
            return
        }

        let fileManager = FileManager.default

        do {
            try fileManager.removeItem(at: directoryURL)
            DevLog.trace(
                "AccountRemoval",
                "deleteAccountDirectory removed directory path=\(directoryURL.path)"
            )
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
                && error.code == NSFileNoSuchFileError
        {
            // Expected case: directory never existed or was already removed.
            DevLog.trace(
                "AccountRemoval",
                "deleteAccountDirectory no-op because directory is absent path=\(directoryURL.path)"
            )
        } catch let error as NSError
            where error.domain == NSPOSIXErrorDomain
                && error.code == Int(ENOENT)
        {
            // POSIX-domain variant of "file not found"; also expected.
            DevLog.trace(
                "AccountRemoval",
                "deleteAccountDirectory no-op because directory is absent path=\(directoryURL.path)"
            )
        } catch {
            DevLog.trace(
                "AccountRemoval",
                "deleteAccountDirectory failed path=\(directoryURL.path) error=\(error.localizedDescription)"
            )
        }
    }
}
