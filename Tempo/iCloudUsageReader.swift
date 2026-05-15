import Foundation

// MARK: - iCloudUsageReader

/// Watches the shared Tempo iCloud documents used by the iPhone companion.
///
/// The reader observes the per-account tree under `Tempo/accounts/` and
/// maintains an in-memory `[accountId: ...]` map for usage, history, and
/// latest session per account. See
/// `openspec/changes/multi-account-support/design.md` for the on-disk
/// layout.
///
/// Account discovery is driven by `Tempo/accounts/index.json`. Per-account
/// payloads live at:
/// - `Tempo/accounts/<percentEncodedAccountId>/usage.json`
/// - `Tempo/accounts/<percentEncodedAccountId>/usage-history.json`
/// - `Tempo/accounts/<percentEncodedAccountId>/latest.json`
/// - `Tempo/accounts/<percentEncodedAccountId>/account.json`
///
/// Alert preferences (`alert-preferences.json`) and the appearance mode
/// file remain global at the `Tempo/` root and are intentionally not
/// partitioned per account.
///
/// The reader intentionally does NOT read the legacy flat paths
/// (`Tempo/usage.json`, `Tempo/usage-history.json`, `Tempo/latest.json`).
/// They may linger in dev iCloud containers from prior builds; developers
/// clean those up manually.
@Observable
@MainActor
final class iCloudUsageReader: NSObject {

    enum SyncStatus {
        case waiting
        case syncing
        case stale(since: Date)
    }

    // MARK: - Per-account state

    /// Latest decoded `UsageState` keyed by canonical accountId.
    var usageByAccount: [String: UsageState] = [:]
    /// Latest decoded history snapshots keyed by canonical accountId; each
    /// array is kept sorted ascending by `date`.
    var historyByAccount: [String: [UsageHistorySnapshot]] = [:]
    /// Latest decoded session info keyed by canonical accountId.
    var sessionByAccount: [String: SessionInfo] = [:]
    /// Last time any per-account `usage.json` was successfully applied,
    /// keyed by accountId.
    var usageUpdatedAtByAccount: [String: Date] = [:]
    /// Last time any per-account `usage-history.json` was successfully
    /// applied, keyed by accountId.
    var historyUpdatedAtByAccount: [String: Date] = [:]
    /// Ordered list of account ids parsed from `accounts/index.json`.
    /// Ordering mirrors the macOS `AccountRegistry` order so consumers can
    /// use position 0 as a sensible default.
    var knownAccountIds: [String] = []

    // MARK: - App-wide sync status

    /// Most recent "any account" usage decode time. Drives the overall
    /// usage sync indicator for the dashboard shell.
    var lastReceivedAt: Date?
    /// Most recent "any account" history decode time.
    var lastHistoryReceivedAt: Date?
    var syncStatus: SyncStatus = .waiting
    var historySyncStatus: SyncStatus = .waiting
    var hasCompletedInitialGather: Bool = false
    var usageReadError: String?
    var historyReadError: String?

    // MARK: - Callbacks
    //
    // The payload types carry `accountId` on them, so callback signatures
    // stay simple. Downstream code routes per accountId by reading
    // `state.accountId` / `session.accountId`.

    var onUsageState: ((UsageState) -> Void)?
    var onSessionInfo: ((SessionInfo) -> Void)?
    var onAlertPreferences: ((SessionAlertPreferences) -> Void)?
    var onAppearanceMode: ((AppearanceMode) -> Void)?
    /// Fires whenever `accounts/index.json` parses successfully, with the
    /// canonical accountId list in registry order. Callers typically use
    /// this to reconcile a persisted "active account" selection (task 5.3).
    var onAccountsIndexUpdated: (([String]) -> Void)?

    private var query: NSMetadataQuery?
    private var latestAlertPreferences: SessionAlertPreferences?
    private var latestAppearanceMode: AppearanceMode?

    private static func debugPrint(_ message: @autoclosure () -> String) {
        _ = message
    }

    // MARK: - Start / Stop

    func start() {
        stop()

        #if targetEnvironment(simulator)
        // Simulator cannot reliably access ubiquity containers; avoid metadata query setup
        // because it triggers CoreServices CRIT container URL logs.
        usageByAccount = [:]
        historyByAccount = [:]
        sessionByAccount = [:]
        usageUpdatedAtByAccount = [:]
        historyUpdatedAtByAccount = [:]
        knownAccountIds = []
        lastReceivedAt = nil
        lastHistoryReceivedAt = nil
        syncStatus = .waiting
        historySyncStatus = .waiting
        hasCompletedInitialGather = true
        let message = Self.unavailableMessage
        usageReadError = message
        historyReadError = message
        DevLog.trace("AlertTrace", "iCloudUsageReader start aborted on simulator message=\(message)")
        return
        #else
        // Apple docs require url(forUbiquityContainerIdentifier:) to run off the main
        // thread. Resolving it synchronously on launch can hang the first SwiftUI frame
        // (especially on a fresh install or with no iCloud account configured).
        DevLog.trace("AlertTrace", "iCloudUsageReader resolving ubiquity container off main thread")
        Task.detached(priority: .userInitiated) { [weak self] in
            let documentsScope = Self.iCloudDocumentsScope()
            await self?.completeStart(documentsScope: documentsScope)
        }
        #endif
    }

    #if !targetEnvironment(simulator)
    private func completeStart(documentsScope: URL?) {
        // Another start() may have been called while the container URL was resolving.
        if query != nil { return }

        let q = NSMetadataQuery()
        // Filename-based predicate. All per-account payloads have stable
        // filenames and live under `Tempo/accounts/...`, while the two
        // global files live at `Tempo/`. We narrow by both filename and
        // path component so the query never matches FileProvider's
        // internal tombstones (for example
        // `/Library/Application Support/FileProvider/<id>/wharf/wharf/delete/<uuid>`),
        // which can briefly appear with the same filenames during an
        // iCloud deletion sync and would otherwise trigger spurious
        // ubiquitous-download requests for files outside our scope.
        let nameFilter = NSPredicate(
            format: "%K IN %@",
            NSMetadataItemFSNameKey,
            [
                "usage.json",
                "usage-history.json",
                "latest.json",
                "account.json",
                "index.json",
                AlertPreferencesSync.fileName,
                AppearanceModeSync.fileName
            ]
        )
        let pathFilter = NSPredicate(
            format: "%K CONTAINS %@",
            NSMetadataItemPathKey,
            "/Documents/Tempo/"
        )
        q.predicate = NSCompoundPredicate(
            andPredicateWithSubpredicates: [nameFilter, pathFilter]
        )
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        if let documentsScope {
            usageReadError = nil
            historyReadError = nil
            Self.debugPrint("iCloudUsageReader start containerDocuments=\(documentsScope.path) queryScope=ubiquitousDocuments")
            DevLog.trace("AlertTrace", "iCloudUsageReader starting query scope=\(documentsScope.path)")
        } else {
            let message = Self.unavailableMessage
            usageReadError = message
            historyReadError = message
            Self.debugPrint("iCloudUsageReader start without container URL; queryScope=ubiquitousDocuments")
            DevLog.trace("AlertTrace", "iCloudUsageReader falling back to ubiquitous documents scope; container unavailable")
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering,
            object: q
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate,
            object: q
        )

        let didStart = q.start()
        Self.debugPrint("iCloudUsageReader query start requested didStart=\(didStart)")
        DevLog.trace("AlertTrace", "iCloudUsageReader query start requested didStart=\(didStart)")
        query = q
        bootstrapReadFromKnownPaths(documentsScope: documentsScope)
    }
    #endif

    func stop() {
        if let q = query {
            Self.debugPrint("iCloudUsageReader stopping query resultCount=\(q.resultCount)")
            DevLog.trace("AlertTrace", "iCloudUsageReader stopping existing query resultCount=\(q.resultCount)")
            NotificationCenter.default.removeObserver(
                self, name: .NSMetadataQueryDidFinishGathering, object: q
            )
            NotificationCenter.default.removeObserver(
                self, name: .NSMetadataQueryDidUpdate, object: q
            )
            q.stop()
        }
        query = nil
    }

    /// Restart the query to pick up iCloud changes that occurred while backgrounded.
    func restart() {
        DevLog.trace("AlertTrace", "iCloudUsageReader restart requested")
        start()
    }

    private static var unavailableMessage: String {
        #if targetEnvironment(simulator)
        "iCloud container is unavailable in iOS Simulator. Use a physical device for live iCloud sync."
        #else
        "iCloud container unavailable (\(TempoICloud.containerIdentifier)). Check iCloud Drive + app container entitlement."
        #endif
    }

    nonisolated private static func iCloudDocumentsScope() -> URL? {
        #if targetEnvironment(simulator)
        // Avoid simulator-only CoreServices CRIT logs for container URL lookups.
        return nil
        #else
        FileManager.default
            .url(forUbiquityContainerIdentifier: TempoICloud.containerIdentifier)?
            .appendingPathComponent("Documents", isDirectory: true)
        #endif
    }

    private func bootstrapReadFromKnownPaths(documentsScope: URL?) {
        guard let documentsScope else { return }
        let trackerDirectory = documentsScope.appendingPathComponent("Tempo", isDirectory: true)
        let accountsDirectory = trackerDirectory.appendingPathComponent("accounts", isDirectory: true)
        let indexURL = accountsDirectory.appendingPathComponent("index.json", isDirectory: false)
        let alertPreferencesURL = trackerDirectory.appendingPathComponent(AlertPreferencesSync.fileName)
        let appearanceModeURL = trackerDirectory.appendingPathComponent(AppearanceModeSync.fileName)

        Self.debugPrint("iCloudUsageReader bootstrap trackerDirectory=\(trackerDirectory.path)")
        DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap trackerDirectory=\(trackerDirectory.path)")

        // FileManager checks + decoding hop off main; results are dispatched back to
        // the @MainActor for state mutation.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let fm = FileManager.default

            // Global files at the Tempo/ root.
            if fm.fileExists(atPath: alertPreferencesURL.path) {
                DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found alert preferences file path=\(alertPreferencesURL.path)")
                await self.readAlertPreferencesFile(at: alertPreferencesURL)
            }
            if fm.fileExists(atPath: appearanceModeURL.path) {
                await self.readAppearanceModeFile(at: appearanceModeURL)
            }

            // Accounts index drives per-account discovery.
            let indexData = fm.fileExists(atPath: indexURL.path)
                ? Self.coordinatedReadResult(at: indexURL)
                : nil
            let accountIds: [String] = {
                guard case .success(let data) = indexData else { return [] }
                guard let decoded = try? Self.jsonDecoder().decode(AccountsIndexFile.self, from: data) else {
                    return []
                }
                return decoded.accountIds
            }()
            if !accountIds.isEmpty {
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader bootstrap parsed accounts index count=\(accountIds.count)"
                )
                await self.applyAccountsIndex(accountIds)
            } else {
                DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found no accounts index at \(indexURL.path)")
            }

            // Read per-account payloads for every accountId listed in the index.
            // Fall back to scanning the accounts directory in case the index
            // hasn't been written yet but per-account files exist.
            let accountsToLoad: [String]
            if accountIds.isEmpty {
                accountsToLoad = Self.listAccountDirectoryNames(under: accountsDirectory)
            } else {
                accountsToLoad = accountIds
            }

            for accountId in accountsToLoad {
                let directoryName = AccountIdentifier.percentEncodedDirectoryName(for: accountId)
                let accountDir = accountsDirectory.appendingPathComponent(directoryName, isDirectory: true)
                let usageURL = accountDir.appendingPathComponent("usage.json")
                let historyURL = accountDir.appendingPathComponent("usage-history.json")
                let sessionURL = accountDir.appendingPathComponent("latest.json")

                if fm.fileExists(atPath: usageURL.path) {
                    await self.readUsageFile(at: usageURL, accountId: accountId)
                }
                if fm.fileExists(atPath: historyURL.path) {
                    await self.readHistoryFile(at: historyURL, accountId: accountId)
                }
                if fm.fileExists(atPath: sessionURL.path) {
                    await self.readSessionFile(at: sessionURL, accountId: accountId)
                }
            }
        }
    }

    /// Scans `Tempo/accounts/` for subdirectories and returns the canonical
    /// accountIds derived from each directory name.
    ///
    /// The percent-encoding applied by
    /// `AccountIdentifier.percentEncodedDirectoryName(for:)` uses only
    /// characters outside `[a-z0-9._@-]`, and `removingPercentEncoding`
    /// reverses it losslessly. Directory names that are not valid
    /// percent-encoded strings are ignored rather than being misinterpreted.
    nonisolated private static func listAccountDirectoryNames(under accountsDirectory: URL) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: accountsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var accountIds: [String] = []
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else { continue }
            let name = entry.lastPathComponent
            guard let decoded = name.removingPercentEncoding else { continue }
            accountIds.append(decoded)
        }
        return accountIds
    }

    // MARK: - Query Callbacks

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        Self.debugPrint("iCloudUsageReader didFinishGathering resultCount=\(query?.resultCount ?? -1)")
        DevLog.trace("AlertTrace", "iCloudUsageReader queryDidFinishGathering resultCount=\(query?.resultCount ?? -1)")
        hasCompletedInitialGather = true
        processQueryResults()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        Self.debugPrint("iCloudUsageReader didUpdate resultCount=\(query?.resultCount ?? -1)")
        DevLog.trace("AlertTrace", "iCloudUsageReader queryDidUpdate resultCount=\(query?.resultCount ?? -1)")
        processQueryResults()
    }

    // MARK: - Process Results

    private func processQueryResults() {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        DevLog.trace("AlertTrace", "iCloudUsageReader processing query results resultCount=\(q.resultCount)")

        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }

            let fileName = (item.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? url.lastPathComponent
            Self.debugPrint("iCloudUsageReader metadata item name=\(fileName) path=\(url.path)")
            DevLog.trace("AlertTrace", "iCloudUsageReader saw metadata item name=\(fileName) path=\(url.path)")
            guard ensureDownloaded(item: item, url: url) else { continue }

            switch fileName {
            case AlertPreferencesSync.fileName:
                readAlertPreferencesFile(at: url)
            case AppearanceModeSync.fileName:
                readAppearanceModeFile(at: url)
            case "index.json":
                guard Self.isUnderAccountsDirectory(url) else { continue }
                readIndexFile(at: url)
            case "account.json":
                guard let accountId = Self.accountId(from: url) else { continue }
                readAccountMetadataFile(at: url, accountId: accountId)
            case "usage.json":
                guard let accountId = Self.accountId(from: url) else { continue }
                readUsageFile(at: url, accountId: accountId)
            case "usage-history.json":
                guard let accountId = Self.accountId(from: url) else { continue }
                readHistoryFile(at: url, accountId: accountId)
            case "latest.json":
                guard let accountId = Self.accountId(from: url) else { continue }
                readSessionFile(at: url, accountId: accountId)
            default:
                continue
            }
        }

        refreshStaleness()
    }

    /// Walks the URL components to find `accounts/<directoryName>/...` and
    /// returns the canonical (percent-decoded) accountId.
    ///
    /// Returns `nil` when the URL is not under the per-account tree (for
    /// example a stray legacy `Tempo/usage.json` at the root).
    nonisolated private static func accountId(from url: URL) -> String? {
        let components = url.pathComponents
        // Need at least `/accounts/<dir>/filename.json`. The first matching
        // `accounts` component wins so we don't trip on future nested
        // directories unintentionally.
        guard let accountsIndex = components.firstIndex(of: "accounts"),
              accountsIndex + 1 < components.count
        else { return nil }
        let directoryName = components[accountsIndex + 1]
        return directoryName.removingPercentEncoding ?? directoryName
    }

    /// Returns `true` when the URL lives under a `Tempo/accounts/` segment.
    /// Used to disambiguate the per-account `index.json` from any same-named
    /// file elsewhere in the container.
    nonisolated private static func isUnderAccountsDirectory(_ url: URL) -> Bool {
        url.pathComponents.contains("accounts")
    }

    private func ensureDownloaded(item: NSMetadataItem, url: URL) -> Bool {
        let downloadStatus = item.value(
            forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
        ) as? String

        DevLog.trace(
            "AlertTrace",
            "iCloudUsageReader ensureDownloaded path=\(url.path) status=\(downloadStatus ?? "nil")"
        )

        if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent {
            return true
        }

        // FileManager I/O off the main thread (we're @MainActor here). The metadata query
        // posts notifications on the main thread, so we can't afford to block it on disk.
        Task.detached(priority: .userInitiated) {
            let isLocalFilePresent = FileManager.default.fileExists(atPath: url.path)
            if !isLocalFilePresent && downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                DevLog.trace("AlertTrace", "iCloudUsageReader requested ubiquitous download path=\(url.path)")
            }
        }
        // Returning true keeps decode attempts opportunistic; coordinatedRead handles
        // the case where the file isn't yet present.
        return true
    }

    // MARK: - File Read (per-account)

    private func readUsageFile(at url: URL, accountId: String) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataResult = Self.coordinatedReadResult(at: url)
            await self?.applyUsageData(dataResult, url: url, accountId: accountId)
        }
    }

    private func applyUsageData(_ result: Result<Data, Error>, url: URL, accountId: String) {
        switch result {
        case .success(let data):
            do {
                let state = try Self.jsonDecoder().decode(UsageState.self, from: data)
                // The file's directory is the source of truth for the
                // accountId. If the payload disagrees, prefer the URL and
                // log once so the mismatch is visible.
                if state.accountId != accountId {
                    DevLog.trace(
                        "AlertTrace",
                        "iCloudUsageReader usage payload accountId=\(state.accountId) does not match directory accountId=\(accountId); using directory"
                    )
                }
                var routed = state
                routed.accountId = accountId
                usageByAccount[accountId] = routed
                let now = Date()
                usageUpdatedAtByAccount[accountId] = now
                lastReceivedAt = now
                usageReadError = nil
                syncStatus = .syncing
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded usage file path=\(url.path) accountId=\(accountId) utilization5h=\(routed.utilization5h) utilization7d=\(routed.utilization7d)"
                )
                onUsageState?(routed)
            } catch {
                usageReadError = error.localizedDescription
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode usage file path=\(url.path) accountId=\(accountId) error=\(error.localizedDescription)")
                refreshStaleness()
            }
        case .failure(let error):
            usageReadError = error.localizedDescription
            DevLog.trace("AlertTrace", "iCloudUsageReader failed to read usage file path=\(url.path) accountId=\(accountId) error=\(error.localizedDescription)")
            refreshStaleness()
        }
    }

    private func readHistoryFile(at url: URL, accountId: String) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataResult = Self.coordinatedReadResult(at: url)
            await self?.applyHistoryData(dataResult, url: url, accountId: accountId)
        }
    }

    private func applyHistoryData(_ result: Result<Data, Error>, url: URL, accountId: String) {
        switch result {
        case .success(let data):
            do {
                let snapshots = try Self.jsonDecoder().decode([UsageHistorySnapshot].self, from: data)
                let sorted = snapshots.sorted { $0.date < $1.date }
                historyByAccount[accountId] = sorted
                let now = Date()
                historyUpdatedAtByAccount[accountId] = now
                lastHistoryReceivedAt = now
                historyReadError = nil
                historySyncStatus = .syncing
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded history file path=\(url.path) accountId=\(accountId) snapshotCount=\(sorted.count)"
                )
            } catch {
                historyReadError = error.localizedDescription
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode history file path=\(url.path) accountId=\(accountId) error=\(error.localizedDescription)")
                refreshStaleness()
            }
        case .failure(let error):
            historyReadError = error.localizedDescription
            DevLog.trace("AlertTrace", "iCloudUsageReader failed to read history file path=\(url.path) accountId=\(accountId) error=\(error.localizedDescription)")
            refreshStaleness()
        }
    }

    private func readSessionFile(at url: URL, accountId: String) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataResult = Self.coordinatedReadResult(at: url)
            await self?.applySessionData(dataResult, url: url, accountId: accountId)
        }
    }

    private func applySessionData(_ result: Result<Data, Error>, url: URL, accountId: String) {
        switch result {
        case .success(let data):
            do {
                let decoded = try Self.jsonDecoder().decode(SessionInfo.self, from: data)
                // Directory wins over payload. Preserves routing when the
                // writer hasn't yet been updated to tag sessions, and
                // tolerates the special `unassigned` bucket.
                let effectiveAccountId = accountId
                let session: SessionInfo
                if decoded.accountId == effectiveAccountId {
                    session = decoded
                } else {
                    DevLog.trace(
                        "AlertTrace",
                        "iCloudUsageReader session payload accountId=\(decoded.accountId) does not match directory accountId=\(effectiveAccountId); using directory"
                    )
                    session = SessionInfo(
                        sessionId: decoded.sessionId,
                        inputTokens: decoded.inputTokens,
                        outputTokens: decoded.outputTokens,
                        costUSD: decoded.costUSD,
                        durationSeconds: decoded.durationSeconds,
                        timestamp: decoded.timestamp,
                        accountId: effectiveAccountId
                    )
                }

                if sessionByAccount[effectiveAccountId]?.sessionId == session.sessionId {
                    DevLog.trace("AlertTrace", "iCloudUsageReader ignored duplicate latest.json accountId=\(effectiveAccountId) sessionId=\(session.sessionId)")
                    return
                }
                sessionByAccount[effectiveAccountId] = session
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded session file path=\(url.path) accountId=\(effectiveAccountId) id=\(session.sessionId) timestamp=\(session.timestamp)"
                )
                onSessionInfo?(session)
            } catch {
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode session file path=\(url.path) accountId=\(accountId) error=\(error.localizedDescription)")
            }
        case .failure(let error):
            DevLog.trace("AlertTrace", "iCloudUsageReader failed to read session file path=\(url.path) accountId=\(accountId) error=\(error.localizedDescription)")
        }
    }

    private func readAccountMetadataFile(at url: URL, accountId: String) {
        // `account.json` is consumed by registry-aware surfaces in a later
        // task. We still acknowledge it here by tracing so iCloud arrival
        // is visible during testing; the accountId is added to
        // `knownAccountIds` if it isn't already there.
        DevLog.trace("AlertTrace", "iCloudUsageReader saw account metadata file path=\(url.path) accountId=\(accountId)")
        if !knownAccountIds.contains(accountId) {
            knownAccountIds.append(accountId)
            onAccountsIndexUpdated?(knownAccountIds)
        }
    }

    private func readIndexFile(at url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataResult = Self.coordinatedReadResult(at: url)
            await self?.applyIndexData(dataResult, url: url)
        }
    }

    private func applyIndexData(_ result: Result<Data, Error>, url: URL) {
        switch result {
        case .success(let data):
            do {
                let decoded = try Self.jsonDecoder().decode(AccountsIndexFile.self, from: data)
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded accounts index path=\(url.path) count=\(decoded.accountIds.count)"
                )
                applyAccountsIndex(decoded.accountIds)
            } catch {
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader failed to decode accounts index path=\(url.path) error=\(error.localizedDescription)"
                )
            }
        case .failure(let error):
            DevLog.trace(
                "AlertTrace",
                "iCloudUsageReader failed to read accounts index path=\(url.path) error=\(error.localizedDescription)"
            )
        }
    }

    private func applyAccountsIndex(_ accountIds: [String]) {
        guard knownAccountIds != accountIds else { return }
        knownAccountIds = accountIds
        onAccountsIndexUpdated?(accountIds)
    }

    private func readAlertPreferencesFile(at url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataResult = Self.coordinatedReadResult(at: url)
            await self?.applyAlertPreferencesData(dataResult, url: url)
        }
    }

    private func applyAlertPreferencesData(_ result: Result<Data, Error>, url: URL) {
        switch result {
        case .success(let data):
            do {
                let preferences = try Self.jsonDecoder().decode(SessionAlertPreferences.self, from: data)
                guard latestAlertPreferences != preferences else {
                    DevLog.trace("AlertTrace", "iCloudUsageReader ignored duplicate alert preferences path=\(url.path)")
                    return
                }
                latestAlertPreferences = preferences
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded alert preferences path=\(url.path) iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
                )
                onAlertPreferences?(preferences)
            } catch {
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode alert preferences path=\(url.path) error=\(error.localizedDescription)")
            }
        case .failure(let error):
            DevLog.trace("AlertTrace", "iCloudUsageReader failed to read alert preferences path=\(url.path) error=\(error.localizedDescription)")
        }
    }

    private func readAppearanceModeFile(at url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataResult = Self.coordinatedReadResult(at: url)
            await self?.applyAppearanceModeData(dataResult)
        }
    }

    private func applyAppearanceModeData(_ result: Result<Data, Error>) {
        guard case .success(let data) = result else { return }
        guard let appearanceMode = try? Self.jsonDecoder().decode(AppearanceMode.self, from: data) else { return }
        guard latestAppearanceMode != appearanceMode else { return }
        latestAppearanceMode = appearanceMode
        onAppearanceMode?(appearanceMode)
    }

    nonisolated private static func jsonDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    nonisolated private static func coordinatedReadResult(at url: URL) -> Result<Data, Error> {
        do {
            return .success(try coordinatedRead(at: url))
        } catch {
            return .failure(error)
        }
    }

    nonisolated private static func coordinatedRead(at url: URL) throws -> Data {
        var coordinationError: NSError?
        var readError: Error?
        var payload: Data?

        NSFileCoordinator().coordinate(readingItemAt: url, error: &coordinationError) { coordinatedURL in
            do {
                payload = try Data(contentsOf: coordinatedURL)
            } catch {
                readError = error
            }
        }

        if let coordinationError {
            throw coordinationError
        }
        if let readError {
            throw readError
        }
        guard let payload else {
            throw CocoaError(.fileReadUnknown)
        }
        return payload
    }

    // MARK: - Staleness Check

    var combinedSyncStatus: SyncStatus {
        switch (syncStatus, historySyncStatus) {
        case (.stale(let date), _), (_, .stale(let date)):
            return .stale(since: date)
        case (.syncing, _), (_, .syncing):
            return .syncing
        default:
            return .waiting
        }
    }

    /// Call periodically to refresh both usage and history staleness flags.
    func refreshStaleness(now: Date = Date()) {
        syncStatus = Self.mapFreshness(ICloudFreshnessPolicy.status(lastReceivedAt: lastReceivedAt, now: now))
        historySyncStatus = Self.mapFreshness(ICloudFreshnessPolicy.status(lastReceivedAt: lastHistoryReceivedAt, now: now))
        DevLog.trace(
            "AlertTrace",
            "iCloudUsageReader refreshed staleness usage=\(Self.describe(syncStatus)) history=\(Self.describe(historySyncStatus))"
        )
    }

    private static func mapFreshness(_ freshness: ICloudDataFreshness) -> SyncStatus {
        switch freshness {
        case .waiting: return .waiting
        case .syncing: return .syncing
        case .stale(let date): return .stale(since: date)
        }
    }

    private static func describe(_ status: SyncStatus) -> String {
        switch status {
        case .waiting:
            "waiting"
        case .syncing:
            "syncing"
        case .stale(let date):
            "stale:\(date.timeIntervalSince1970)"
        }
    }
}
