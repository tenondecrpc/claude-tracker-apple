import Foundation

// MARK: - iCloudUsageReader

/// Watches `usage.json` and `usage-history.json` in the shared iCloud ubiquity container.
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

    private var query: NSMetadataQuery?

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
        return
        #endif

        let q = NSMetadataQuery()
        q.predicate = NSPredicate(
            format: "%K IN %@", NSMetadataItemFSNameKey, ["usage.json", "usage-history.json", "latest.json"]
        )
        let documentsScope = Self.iCloudDocumentsScope()
        if let documentsScope {
            q.searchScopes = [documentsScope]
            usageReadError = nil
            historyReadError = nil
        } else {
            q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
            let message = Self.unavailableMessage
            usageReadError = message
            historyReadError = message
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

        q.start()
        query = q
        bootstrapReadFromKnownPaths(documentsScope: documentsScope)
    }

    func stop() {
        if let q = query {
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
        start()
    }

    private static var unavailableMessage: String {
        #if targetEnvironment(simulator)
        "iCloud container is unavailable in iOS Simulator. Use a physical device for live iCloud sync."
        #else
        "iCloud container unavailable (\(ClaudeTrackerICloud.containerIdentifier)). Check iCloud Drive + app container entitlement."
        #endif
    }

    private static func iCloudDocumentsScope() -> URL? {
        #if targetEnvironment(simulator)
        // Avoid simulator-only CoreServices CRIT logs for container URL lookups.
        return nil
        #else
        FileManager.default
            .url(forUbiquityContainerIdentifier: ClaudeTrackerICloud.containerIdentifier)?
            .appendingPathComponent("Documents", isDirectory: true)
        #endif
    }

    private func bootstrapReadFromKnownPaths(documentsScope: URL?) {
        guard let documentsScope else { return }
        let trackerDirectory = documentsScope.appendingPathComponent("ClaudeTracker", isDirectory: true)

        let usageURL = trackerDirectory.appendingPathComponent("usage.json")
        if FileManager.default.fileExists(atPath: usageURL.path) {
            readUsageFile(at: usageURL)
        }

        let historyURL = trackerDirectory.appendingPathComponent("usage-history.json")
        if FileManager.default.fileExists(atPath: historyURL.path) {
            readHistoryFile(at: historyURL)
        }

        let sessionURL = trackerDirectory.appendingPathComponent("latest.json")
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            readSessionFile(at: sessionURL)
        }
    }

    // MARK: - Query Callbacks

    @objc private func queryDidFinishGathering(_ notification: Notification) {
        processQueryResults()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        processQueryResults()
    }

    // MARK: - Process Results

    private func processQueryResults() {
        guard let q = query else { return }
        q.disableUpdates()
        defer { q.enableUpdates() }

        for i in 0..<q.resultCount {
            guard let item = q.result(at: i) as? NSMetadataItem,
                  let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }

            let fileName = (item.value(forAttribute: NSMetadataItemFSNameKey) as? String) ?? url.lastPathComponent
            guard fileName == "usage.json" || fileName == "usage-history.json" || fileName == "latest.json" else { continue }
            guard ensureDownloaded(item: item, url: url) else { continue }

            if fileName == "usage.json" {
                readUsageFile(at: url)
            } else if fileName == "usage-history.json" {
                readHistoryFile(at: url)
            } else {
                readSessionFile(at: url)
            }
        }

        refreshStaleness()
    }

    private func ensureDownloaded(item: NSMetadataItem, url: URL) -> Bool {
        let downloadStatus = item.value(
            forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
        ) as? String

        if downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
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
                self.onUsageState?(state)
            case .failure(let error):
                self.usageReadError = error.localizedDescription
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
            case .failure(let error):
                self.historyReadError = error.localizedDescription
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
                    return
                }
                self.latestSession = session
                self.onSessionInfo?(session)
            case .failure:
                break
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
    }

    private static func mapFreshness(_ freshness: ICloudDataFreshness) -> SyncStatus {
        switch freshness {
        case .waiting: return .waiting
        case .syncing: return .syncing
        case .stale(let date): return .stale(since: date)
        }
    }
}
