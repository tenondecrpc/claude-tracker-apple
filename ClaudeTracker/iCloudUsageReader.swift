import Foundation

// MARK: - iCloudUsageReader

/// Watches `ClaudeTracker/usage.json` in the shared iCloud ubiquity container via
/// `NSMetadataQuery`. When the file changes, decodes `UsageState` and fires `onUsageState`.
///
/// The macOS ClaudeTracker app is responsible for writing this file after each usage poll.
@Observable
@MainActor
final class iCloudUsageReader: NSObject {

    enum SyncStatus {
        case waiting   // No file detected yet
        case syncing   // File present and fresh (< 30 min old)
        case stale(since: Date)  // File older than 30 minutes
    }

    var syncStatus: SyncStatus = .waiting
    var lastReceivedAt: Date?

    var onUsageState: ((UsageState) -> Void)?

    private var query: NSMetadataQuery?

    // MARK: - Start / Stop

    func start() {
        stop()

        let q = NSMetadataQuery()
        q.predicate = NSPredicate(
            format: "%K == %@", NSMetadataItemFSNameKey, "usage.json"
        )
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

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

            let downloadStatus = item.value(
                forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey
            ) as? String

            if downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                // File not yet downloaded — request it and wait for next update (Task 5.2)
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                continue
            }

            readFile(at: url)
        }
    }

    // MARK: - File Read

    private func readFile(at url: URL) {
        Task.detached { [weak self] in
            var coordinatorError: NSError?
            var decoded: UsageState?

            NSFileCoordinator().coordinate(readingItemAt: url, error: &coordinatorError) { coordURL in
                guard let data = try? Data(contentsOf: coordURL) else { return }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                decoded = try? decoder.decode(UsageState.self, from: data)
            }

            guard let state = decoded else { return }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.lastReceivedAt = Date()
                self.syncStatus = .syncing
                self.onUsageState?(state)
            }
        }
    }

    // MARK: - Staleness Check

    /// Call periodically (e.g., from a timer or `TimelineView`) to refresh staleness status.
    func refreshStaleness() {
        guard let receivedAt = lastReceivedAt else {
            syncStatus = .waiting
            return
        }
        let age = Date().timeIntervalSince(receivedAt)
        syncStatus = age > 30 * 60 ? .stale(since: receivedAt) : .syncing
    }
}
