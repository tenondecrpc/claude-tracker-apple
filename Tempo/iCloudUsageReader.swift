import Foundation

// MARK: - iCloudUsageReader

/// Watches shared Tempo iCloud documents used by the iPhone companion.
/// Decoded usage state drives dashboard/watch relay; history drives activity charts.
@Observable
@MainActor
final class iCloudUsageReader: NSObject {

    enum SyncStatus {
        case waiting
        case syncing
        case stale(since: Date)
    }

    var syncStatus: SyncStatus = .waiting
    var historySyncStatus: SyncStatus = .waiting
    var lastReceivedAt: Date?
    var lastHistoryReceivedAt: Date?
    var hasCompletedInitialGather: Bool = false
    var latestUsage: UsageState?
    var latestSession: SessionInfo?
    var historySnapshots: [UsageHistorySnapshot] = []
    var usageReadError: String?
    var historyReadError: String?

    var onUsageState: ((UsageState) -> Void)?
    var onSessionInfo: ((SessionInfo) -> Void)?
    var onAlertPreferences: ((SessionAlertPreferences) -> Void)?
    var onAppearanceMode: ((AppearanceMode) -> Void)?

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
        latestUsage = nil
        latestSession = nil
        historySnapshots = []
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
        q.predicate = NSPredicate(
            format: "%K IN %@",
            NSMetadataItemFSNameKey,
            ["usage.json", "usage-history.json", "latest.json", AlertPreferencesSync.fileName, AppearanceModeSync.fileName]
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

    /// Restart the query to pick up iCloud changes that occurred while backgrounded (Task 5.3).
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
        Self.debugPrint("iCloudUsageReader bootstrap trackerDirectory=\(trackerDirectory.path)")
        DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap trackerDirectory=\(trackerDirectory.path)")

        let usageURL = trackerDirectory.appendingPathComponent("usage.json")
        let historyURL = trackerDirectory.appendingPathComponent("usage-history.json")
        let sessionURL = trackerDirectory.appendingPathComponent("latest.json")
        let alertPreferencesURL = trackerDirectory.appendingPathComponent(AlertPreferencesSync.fileName)
        let appearanceModeURL = trackerDirectory.appendingPathComponent(AppearanceModeSync.fileName)

        // FileManager checks + decoding hop off main; results are dispatched back to
        // the @MainActor for state mutation.
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            let foundUsage = fm.fileExists(atPath: usageURL.path)
            let foundHistory = fm.fileExists(atPath: historyURL.path)
            let foundSession = fm.fileExists(atPath: sessionURL.path)
            let foundAlertPrefs = fm.fileExists(atPath: alertPreferencesURL.path)
            let foundAppearance = fm.fileExists(atPath: appearanceModeURL.path)

            if foundUsage {
                DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found usage file path=\(usageURL.path)")
                await self.readUsageFile(at: usageURL)
            }
            if foundHistory {
                DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found history file path=\(historyURL.path)")
                await self.readHistoryFile(at: historyURL)
            }
            if foundSession {
                DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found session file path=\(sessionURL.path)")
                await self.readSessionFile(at: sessionURL)
            }
            if foundAlertPrefs {
                DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found alert preferences file path=\(alertPreferencesURL.path)")
                await self.readAlertPreferencesFile(at: alertPreferencesURL)
            }
            if foundAppearance {
                await self.readAppearanceModeFile(at: appearanceModeURL)
            }
        }
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
            guard fileName == "usage.json"
                || fileName == "usage-history.json"
                || fileName == "latest.json"
                || fileName == AlertPreferencesSync.fileName
                || fileName == AppearanceModeSync.fileName
            else { continue }
            Self.debugPrint("iCloudUsageReader metadata item name=\(fileName) path=\(url.path)")
            DevLog.trace("AlertTrace", "iCloudUsageReader saw metadata item name=\(fileName) path=\(url.path)")
            guard ensureDownloaded(item: item, url: url) else { continue }

            if fileName == "usage.json" {
                readUsageFile(at: url)
            } else if fileName == "usage-history.json" {
                readHistoryFile(at: url)
            } else if fileName == "latest.json" {
                readSessionFile(at: url)
            } else if fileName == AlertPreferencesSync.fileName {
                readAlertPreferencesFile(at: url)
            } else {
                readAppearanceModeFile(at: url)
            }
        }

        refreshStaleness()
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

    // MARK: - File Read

    private func readUsageFile(at url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataResult = Self.coordinatedReadResult(at: url)
            await self?.applyUsageData(dataResult, url: url)
        }
    }

    private func applyUsageData(_ result: Result<Data, Error>, url: URL) {
        switch result {
        case .success(let data):
            do {
                let state = try Self.jsonDecoder().decode(UsageState.self, from: data)
                latestUsage = state
                lastReceivedAt = Date()
                usageReadError = nil
                syncStatus = .syncing
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded usage file path=\(url.path) utilization5h=\(state.utilization5h) utilization7d=\(state.utilization7d)"
                )
                onUsageState?(state)
            } catch {
                usageReadError = error.localizedDescription
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode usage file path=\(url.path) error=\(error.localizedDescription)")
                refreshStaleness()
            }
        case .failure(let error):
            usageReadError = error.localizedDescription
            DevLog.trace("AlertTrace", "iCloudUsageReader failed to read usage file path=\(url.path) error=\(error.localizedDescription)")
            refreshStaleness()
        }
    }

    private func readHistoryFile(at url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataResult = Self.coordinatedReadResult(at: url)
            await self?.applyHistoryData(dataResult, url: url)
        }
    }

    private func applyHistoryData(_ result: Result<Data, Error>, url: URL) {
        switch result {
        case .success(let data):
            do {
                let snapshots = try Self.jsonDecoder().decode([UsageHistorySnapshot].self, from: data)
                historySnapshots = snapshots.sorted { $0.date < $1.date }
                lastHistoryReceivedAt = Date()
                historyReadError = nil
                historySyncStatus = .syncing
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded history file path=\(url.path) snapshotCount=\(snapshots.count)"
                )
            } catch {
                historyReadError = error.localizedDescription
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode history file path=\(url.path) error=\(error.localizedDescription)")
                refreshStaleness()
            }
        case .failure(let error):
            historyReadError = error.localizedDescription
            DevLog.trace("AlertTrace", "iCloudUsageReader failed to read history file path=\(url.path) error=\(error.localizedDescription)")
            refreshStaleness()
        }
    }

    private func readSessionFile(at url: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let dataResult = Self.coordinatedReadResult(at: url)
            await self?.applySessionData(dataResult, url: url)
        }
    }

    private func applySessionData(_ result: Result<Data, Error>, url: URL) {
        switch result {
        case .success(let data):
            do {
                let session = try Self.jsonDecoder().decode(SessionInfo.self, from: data)
                if latestSession?.sessionId == session.sessionId {
                    DevLog.trace("AlertTrace", "iCloudUsageReader ignored duplicate latest.json session id=\(session.sessionId)")
                    return
                }
                latestSession = session
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded session file path=\(url.path) id=\(session.sessionId) timestamp=\(session.timestamp)"
                )
                onSessionInfo?(session)
            } catch {
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode session file path=\(url.path) error=\(error.localizedDescription)")
            }
        case .failure(let error):
            DevLog.trace("AlertTrace", "iCloudUsageReader failed to read session file path=\(url.path) error=\(error.localizedDescription)")
        }
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
