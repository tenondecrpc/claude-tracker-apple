import Foundation

@Observable
@MainActor
final class IOSAppStore {
    let iCloudReader: iCloudUsageReader

    var historyRange: UsageHistoryRange {
        didSet { defaults.set(historyRange.rawValue, forKey: Keys.historyRange) }
    }
    var showSessionSeries: Bool {
        didSet { defaults.set(showSessionSeries, forKey: Keys.showSessionSeries) }
    }
    var showWeeklySeries: Bool {
        didSet { defaults.set(showWeeklySeries, forKey: Keys.showWeeklySeries) }
    }
    var use24HourTime: Bool {
        didSet { defaults.set(use24HourTime, forKey: Keys.use24HourTime) }
    }

    var usage: UsageState? { iCloudReader.latestUsage }
    var historySnapshots: [UsageHistorySnapshot] { iCloudReader.historySnapshots }
    var filteredHistorySnapshots: [UsageHistorySnapshot] {
        UsageHistoryTransformer.filteredSnapshots(
            iCloudReader.historySnapshots,
            range: historyRange
        )
    }

    var usageSyncStatus: iCloudUsageReader.SyncStatus {
        Self.map(ICloudFreshnessPolicy.status(lastReceivedAt: iCloudReader.lastReceivedAt))
    }
    var historySyncStatus: iCloudUsageReader.SyncStatus {
        Self.map(ICloudFreshnessPolicy.status(lastReceivedAt: iCloudReader.lastHistoryReceivedAt))
    }
    var combinedSyncStatus: iCloudUsageReader.SyncStatus {
        switch (usageSyncStatus, historySyncStatus) {
        case (.stale(let date), _), (_, .stale(let date)):
            return .stale(since: date)
        case (.syncing, _), (_, .syncing):
            return .syncing
        default:
            return .waiting
        }
    }

    var lastUsageUpdate: Date? { iCloudReader.lastReceivedAt }
    var lastHistoryUpdate: Date? { iCloudReader.lastHistoryReceivedAt }

    var usageReadError: String? { iCloudReader.usageReadError }
    var historyReadError: String? { iCloudReader.historyReadError }

    private(set) var isWatchPaired = false
    private(set) var isWatchAppInstalled = false

    func updateWatchState(isPaired: Bool, isInstalled: Bool) {
        isWatchPaired = isPaired
        isWatchAppInstalled = isInstalled
    }

    var isHistoryStaleWhileUsageFresh: Bool {
        if case .syncing = usageSyncStatus, case .stale = historySyncStatus {
            return true
        }
        return false
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let historyRange = "ios.historyRange"
        static let showSessionSeries = "ios.showSessionSeries"
        static let showWeeklySeries = "ios.showWeeklySeries"
        static let use24HourTime = "ios.use24HourTime"
    }

    init(iCloudReader: iCloudUsageReader, defaults: UserDefaults = .standard) {
        self.iCloudReader = iCloudReader
        self.defaults = defaults

        if let savedRange = defaults.string(forKey: Keys.historyRange),
           let parsedRange = UsageHistoryRange(rawValue: savedRange) {
            historyRange = parsedRange
        } else {
            historyRange = .last7Days
        }

        if defaults.object(forKey: Keys.showSessionSeries) == nil {
            showSessionSeries = true
        } else {
            showSessionSeries = defaults.bool(forKey: Keys.showSessionSeries)
        }

        if defaults.object(forKey: Keys.showWeeklySeries) == nil {
            showWeeklySeries = true
        } else {
            showWeeklySeries = defaults.bool(forKey: Keys.showWeeklySeries)
        }

        if defaults.object(forKey: Keys.use24HourTime) == nil {
            use24HourTime = false
        } else {
            use24HourTime = defaults.bool(forKey: Keys.use24HourTime)
        }
    }

    func refreshStaleness() {
        iCloudReader.refreshStaleness()
    }

    private static func map(_ freshness: ICloudDataFreshness) -> iCloudUsageReader.SyncStatus {
        switch freshness {
        case .waiting: return .waiting
        case .syncing: return .syncing
        case .stale(let date): return .stale(since: date)
        }
    }
}
