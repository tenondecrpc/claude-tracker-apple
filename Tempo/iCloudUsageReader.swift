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
    var latestUsage: UsageState?
    var latestSession: SessionInfo?
    var historySnapshots: [UsageHistorySnapshot] = []
    var usageReadError: String?
    var historyReadError: String?

    var onUsageState: ((UsageState) -> Void)?
    var onSessionInfo: ((SessionInfo) -> Void)?
    var onAlertPreferences: ((SessionAlertPreferences) -> Void)?

    private var query: NSMetadataQuery?
    private var latestAlertPreferences: SessionAlertPreferences?

    private static func debugPrint(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Tempo iOS] \(message())")
        #endif
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
        let message = Self.unavailableMessage
        usageReadError = message
        historyReadError = message
        DevLog.trace("AlertTrace", "iCloudUsageReader start aborted on simulator message=\(message)")
        return
        #endif

        let q = NSMetadataQuery()
        q.predicate = NSPredicate(
            format: "%K IN %@", NSMetadataItemFSNameKey, ["usage.json", "usage-history.json", "latest.json", AlertPreferencesSync.fileName]
        )
        let documentsScope = Self.iCloudDocumentsScope()
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

    private static func iCloudDocumentsScope() -> URL? {
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
        if FileManager.default.fileExists(atPath: usageURL.path) {
            Self.debugPrint("iCloudUsageReader bootstrap found usage.json")
            DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found usage file path=\(usageURL.path)")
            readUsageFile(at: usageURL)
        }

        let historyURL = trackerDirectory.appendingPathComponent("usage-history.json")
        if FileManager.default.fileExists(atPath: historyURL.path) {
            Self.debugPrint("iCloudUsageReader bootstrap found usage-history.json")
            DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found history file path=\(historyURL.path)")
            readHistoryFile(at: historyURL)
        }

        let sessionURL = trackerDirectory.appendingPathComponent("latest.json")
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            Self.debugPrint("iCloudUsageReader bootstrap found latest.json")
            DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found session file path=\(sessionURL.path)")
            readSessionFile(at: sessionURL)
        }

        let alertPreferencesURL = trackerDirectory.appendingPathComponent(AlertPreferencesSync.fileName)
        if FileManager.default.fileExists(atPath: alertPreferencesURL.path) {
            Self.debugPrint("iCloudUsageReader bootstrap found alert-preferences.json")
            DevLog.trace("AlertTrace", "iCloudUsageReader bootstrap found alert preferences file path=\(alertPreferencesURL.path)")
            readAlertPreferencesFile(at: alertPreferencesURL)
        }
    }

    // MARK: - Query Callbacks

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        Self.debugPrint("iCloudUsageReader didFinishGathering resultCount=\(query?.resultCount ?? -1)")
        DevLog.trace("AlertTrace", "iCloudUsageReader queryDidFinishGathering resultCount=\(query?.resultCount ?? -1)")
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
            } else {
                readAlertPreferencesFile(at: url)
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

        let isLocalFilePresent = FileManager.default.fileExists(atPath: url.path)
        Self.debugPrint(
            "iCloudUsageReader ensureDownloaded path=\(url.lastPathComponent) status=\(downloadStatus ?? "nil") localExists=\(isLocalFilePresent)"
        )

        if downloadStatus == NSMetadataUbiquitousItemDownloadingStatusCurrent || isLocalFilePresent {
            return true
        }

        if downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            Self.debugPrint("iCloudUsageReader requested download for \(url.lastPathComponent)")
            DevLog.trace("AlertTrace", "iCloudUsageReader requested ubiquitous download path=\(url.path)")
            return false
        }
        return true
    }

    // MARK: - File Read

    private func readUsageFile(at url: URL) {
        Task { [weak self] in
            let result: Result<UsageState, Error> = Self.decodeFile(at: url, as: UsageState.self)

            guard let self else { return }
            switch result {
            case .success(let state):
                self.latestUsage = state
                self.lastReceivedAt = Date()
                self.usageReadError = nil
                self.syncStatus = .syncing
                Self.debugPrint("iCloudUsageReader decoded usage.json utilization5h=\(state.utilization5h) utilization7d=\(state.utilization7d)")
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded usage file path=\(url.path) utilization5h=\(state.utilization5h) utilization7d=\(state.utilization7d)"
                )
                self.onUsageState?(state)
            case .failure(let error):
                self.usageReadError = error.localizedDescription
                Self.debugPrint("iCloudUsageReader failed usage.json decode error=\(error.localizedDescription)")
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode usage file path=\(url.path) error=\(error.localizedDescription)")
                self.refreshStaleness()
            }
        }
    }

    private func readHistoryFile(at url: URL) {
        Task { [weak self] in
            let result: Result<[UsageHistorySnapshot], Error> = Self.decodeFile(at: url, as: [UsageHistorySnapshot].self)

            guard let self else { return }
            switch result {
            case .success(let snapshots):
                self.historySnapshots = snapshots.sorted { $0.date < $1.date }
                self.lastHistoryReceivedAt = Date()
                self.historyReadError = nil
                self.historySyncStatus = .syncing
                Self.debugPrint("iCloudUsageReader decoded usage-history.json count=\(snapshots.count)")
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded history file path=\(url.path) snapshotCount=\(snapshots.count)"
                )
            case .failure(let error):
                self.historyReadError = error.localizedDescription
                Self.debugPrint("iCloudUsageReader failed usage-history.json decode error=\(error.localizedDescription)")
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode history file path=\(url.path) error=\(error.localizedDescription)")
                self.refreshStaleness()
            }
        }
    }

    private func readSessionFile(at url: URL) {
        Task { [weak self] in
            let result: Result<SessionInfo, Error> = Self.decodeFile(at: url, as: SessionInfo.self)

            guard let self else { return }
            switch result {
            case .success(let session):
                if self.latestSession?.sessionId == session.sessionId {
                    Self.debugPrint("iCloudUsageReader ignored duplicate latest.json session id=\(session.sessionId)")
                    DevLog.trace("AlertTrace", "iCloudUsageReader ignored duplicate latest.json session id=\(session.sessionId)")
                    return
                }
                self.latestSession = session
                Self.debugPrint(
                    "iCloudUsageReader decoded latest.json session id=\(session.sessionId) duration=\(session.durationSeconds)s tokens=\(session.inputTokens + session.outputTokens)"
                )
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded session file path=\(url.path) id=\(session.sessionId) timestamp=\(session.timestamp)"
                )
                self.onSessionInfo?(session)
            case .failure(let error):
                Self.debugPrint("iCloudUsageReader failed latest.json decode error=\(error.localizedDescription)")
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode session file path=\(url.path) error=\(error.localizedDescription)")
            }
        }
    }

    private func readAlertPreferencesFile(at url: URL) {
        Task { [weak self] in
            let result: Result<SessionAlertPreferences, Error> = Self.decodeFile(at: url, as: SessionAlertPreferences.self)

            guard let self else { return }
            switch result {
            case .success(let preferences):
                guard self.latestAlertPreferences != preferences else {
                    Self.debugPrint("iCloudUsageReader ignored duplicate alert-preferences.json")
                    DevLog.trace("AlertTrace", "iCloudUsageReader ignored duplicate alert preferences path=\(url.path)")
                    return
                }
                self.latestAlertPreferences = preferences
                Self.debugPrint(
                    "iCloudUsageReader decoded alert-preferences.json iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
                )
                DevLog.trace(
                    "AlertTrace",
                    "iCloudUsageReader decoded alert preferences path=\(url.path) iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
                )
                self.onAlertPreferences?(preferences)
            case .failure(let error):
                Self.debugPrint("iCloudUsageReader failed alert-preferences.json decode error=\(error.localizedDescription)")
                DevLog.trace("AlertTrace", "iCloudUsageReader failed to decode alert preferences path=\(url.path) error=\(error.localizedDescription)")
            }
        }
    }

    private static func decodeFile<T: Decodable>(at url: URL, as type: T.Type) -> Result<T, Error> {
        do {
            let data = try coordinatedRead(at: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return .success(try decoder.decode(type, from: data))
        } catch {
            return .failure(error)
        }
    }

    private static func coordinatedRead(at url: URL) throws -> Data {
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
