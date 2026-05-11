import Foundation
import SwiftUI

@Observable
@MainActor
final class IOSAppStore {
    let iCloudReader: iCloudUsageReader
    private var isApplyingSyncedAlertPreferences = false

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
    var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode)
        }
    }
    var iPhoneAlertsEnabled: Bool {
        didSet {
            defaults.set(iPhoneAlertsEnabled, forKey: Keys.iPhoneAlertsEnabled)
            if !isApplyingSyncedAlertPreferences {
                onSessionAlertPreferencesChange?(sessionAlertPreferences)
            }
        }
    }
    var watchAlertsEnabled: Bool {
        didSet {
            defaults.set(watchAlertsEnabled, forKey: Keys.watchAlertsEnabled)
            if !isApplyingSyncedAlertPreferences {
                onSessionAlertPreferencesChange?(sessionAlertPreferences)
            }
        }
    }

    private(set) var isDemoMode = false
    private var demoUsage: UsageState?
    private var demoHistory: [UsageHistorySnapshot] = []

    /// Persisted iOS active account selection. `nil` means "no active
    /// account chosen yet", which resolves to the first discovered account
    /// in `iCloudReader.knownAccountIds` (see `resolvedAccountId`).
    ///
    /// Written via `setActiveAccount(accountId:)` so the change propagates
    /// through `onActiveAccountChange`. Direct writes are supported for
    /// SwiftUI bindings that need it but route through `didSet` to persist
    /// to UserDefaults under `Keys.activeAccountId`.
    var activeAccountId: String? {
        didSet {
            if activeAccountId == oldValue { return }
            if let id = activeAccountId {
                defaults.set(id, forKey: Keys.activeAccountId)
            } else {
                defaults.removeObject(forKey: Keys.activeAccountId)
            }
        }
    }

    var usage: UsageState? { isDemoMode ? demoUsage : activeAccountUsage }
    var historySnapshots: [UsageHistorySnapshot] {
        isDemoMode ? demoHistory : activeAccountHistory
    }
    var filteredHistorySnapshots: [UsageHistorySnapshot] {
        UsageHistoryTransformer.filteredSnapshots(
            historySnapshots,
            range: historyRange
        )
    }

    /// Returns the accountId that per-account reads should target.
    ///
    /// Precedence:
    /// 1. `activeAccountId` when it is still present in
    ///    `iCloudReader.knownAccountIds` (user explicitly picked it, and it
    ///    has not been removed on macOS).
    /// 2. The first entry of `iCloudReader.knownAccountIds` (registry
    ///    order on macOS), which is the "first discovered account" default
    ///    called out in task 5.3.
    /// 3. Any accountId present in `usageByAccount` sorted lexically, as a
    ///    last resort when the registry index hasn't arrived yet but
    ///    per-account files already have.
    var resolvedAccountId: String? {
        if let id = activeAccountId,
           iCloudReader.knownAccountIds.contains(id) {
            return id
        }
        if let first = iCloudReader.knownAccountIds.first {
            return first
        }
        return iCloudReader.usageByAccount.keys.sorted().first
    }

    private var activeAccountUsage: UsageState? {
        guard let accountId = resolvedAccountId else { return nil }
        return iCloudReader.usageByAccount[accountId]
    }

    private var activeAccountHistory: [UsageHistorySnapshot] {
        guard let accountId = resolvedAccountId else { return [] }
        return iCloudReader.historyByAccount[accountId] ?? []
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
    var onSessionAlertPreferencesChange: ((SessionAlertPreferences) -> Void)?
    /// Fires when the user changes the iOS active account selection
    /// (including a programmatic reset to `nil` when the current active id
    /// vanishes from `knownAccountIds`). The coordinator listens for this
    /// to re-send the active account's usage state to the watch and
    /// refresh the iOS widget snapshot.
    var onActiveAccountChange: ((String?) -> Void)?

    func updateWatchState(isPaired: Bool, isInstalled: Bool) {
        isWatchPaired = isPaired
        isWatchAppInstalled = isInstalled
    }

    var isInitialSyncInProgress: Bool {
        if isDemoMode { return false }
        return !iCloudReader.hasCompletedInitialGather
            && iCloudReader.usageReadError == nil
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
        static let appearanceMode = "ios.appearanceMode"
        static let iPhoneAlertsEnabled = "ios.iPhoneAlertsEnabled"
        static let watchAlertsEnabled = "ios.watchAlertsEnabled"
        static let activeAccountId = "ios.activeAccountId"
    }

    var preferredColorScheme: ColorScheme? { appearanceMode.colorScheme }

    var sessionAlertPreferences: SessionAlertPreferences {
        SessionAlertPreferences(
            iPhoneAlertsEnabled: iPhoneAlertsEnabled,
            watchAlertsEnabled: watchAlertsEnabled
        )
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
            use24HourTime = true
        } else {
            use24HourTime = defaults.bool(forKey: Keys.use24HourTime)
        }

        if let rawAppearanceMode = defaults.string(forKey: Keys.appearanceMode),
           let parsedAppearanceMode = AppearanceMode(rawValue: rawAppearanceMode) {
            appearanceMode = parsedAppearanceMode
        } else {
            appearanceMode = .dark
        }

        if defaults.object(forKey: Keys.iPhoneAlertsEnabled) == nil {
            iPhoneAlertsEnabled = SessionAlertPreferences.default.iPhoneAlertsEnabled
        } else {
            iPhoneAlertsEnabled = defaults.bool(forKey: Keys.iPhoneAlertsEnabled)
        }

        if defaults.object(forKey: Keys.watchAlertsEnabled) == nil {
            watchAlertsEnabled = SessionAlertPreferences.default.watchAlertsEnabled
        } else {
            watchAlertsEnabled = defaults.bool(forKey: Keys.watchAlertsEnabled)
        }

        // Load persisted active account selection. A persisted id that
        // does not match any currently known account is still kept: the
        // coordinator reconciles it when `onAccountsIndexUpdated` fires
        // so we don't silently drop a selection that will become valid
        // seconds later when the index finishes downloading.
        if let storedActiveAccountId = defaults.string(forKey: Keys.activeAccountId),
           !storedActiveAccountId.isEmpty {
            activeAccountId = storedActiveAccountId
        } else {
            activeAccountId = nil
        }
    }

    func refreshStaleness() {
        iCloudReader.refreshStaleness()
    }

    // MARK: - Active Account

    /// Updates the iOS active account selection and notifies observers.
    ///
    /// - Parameter accountId: canonical accountId (email-normalized) or
    ///   `nil` to clear the selection. No validation against
    ///   `knownAccountIds` happens here; `resolvedAccountId` handles that
    ///   and the coordinator reconciles the persisted id when the
    ///   iCloud-discovered accounts index arrives.
    ///
    /// No-ops when the value is unchanged so we don't spam the coordinator
    /// with redundant watch relay / widget writes. The persistence is done
    /// in the `activeAccountId` `didSet`.
    func setActiveAccount(accountId: String?) {
        let normalized: String? = {
            guard let id = accountId, !id.isEmpty else { return nil }
            return id
        }()
        if activeAccountId == normalized { return }
        activeAccountId = normalized
        onActiveAccountChange?(normalized)
    }

    // MARK: - Demo Mode

    /// Loads mock data so reviewers (and users without an iCloud-connected Mac)
    /// can preview the dashboard. Demo data is in-memory only and never written
    /// to iCloud, widgets, or the watch.
    func enterDemoMode() {
        isDemoMode = true
        demoUsage = UsageState(
            accountId: "demo@example.com",
            utilization5h: 0.68,
            utilization7d: 0.42,
            resetAt5h: Date().addingTimeInterval(2 * 3600),
            resetAt7d: Date().addingTimeInterval(5 * 24 * 3600),
            isMocked: true,
            extraUsage: nil,
            isDoubleLimitPromoActive: false
        )
        demoHistory = Self.makeDemoHistory()
    }

    func exitDemoMode() {
        isDemoMode = false
        demoUsage = nil
        demoHistory = []
    }

    private static func makeDemoHistory() -> [UsageHistorySnapshot] {
        let now = Date()
        // 7 days of points spaced ~2h apart, with a believable usage curve.
        let count = 7 * 12
        return (0..<count).map { i in
            let offsetSeconds = Double(count - i) * (2 * 3600)
            let date = now.addingTimeInterval(-offsetSeconds)
            let progress = Double(i) / Double(count)
            let session = max(0.05, min(0.95, 0.2 + 0.7 * progress + 0.1 * sin(Double(i) * 0.7)))
            let weekly = max(0.05, min(0.9, 0.1 + 0.5 * progress))
            return UsageHistorySnapshot(
                date: date,
                utilization5h: session,
                utilization7d: weekly
            )
        }
    }

    func applySyncedAlertPreferences(_ preferences: SessionAlertPreferences) {
        guard sessionAlertPreferences != preferences else {
            DevLog.trace(
                "AlertTrace",
                "IOSAppStore received unchanged synced preferences iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
            )
            return
        }

        DevLog.trace(
            "AlertTrace",
            "IOSAppStore applying synced preferences oldIPhone=\(iPhoneAlertsEnabled) oldWatch=\(watchAlertsEnabled) newIPhone=\(preferences.iPhoneAlertsEnabled) newWatch=\(preferences.watchAlertsEnabled)"
        )
        isApplyingSyncedAlertPreferences = true
        iPhoneAlertsEnabled = preferences.iPhoneAlertsEnabled
        watchAlertsEnabled = preferences.watchAlertsEnabled
        isApplyingSyncedAlertPreferences = false

        onSessionAlertPreferencesChange?(sessionAlertPreferences)
    }

    func applySyncedAppearanceMode(_ appearanceMode: AppearanceMode) {
        guard self.appearanceMode != appearanceMode else { return }

        self.appearanceMode = appearanceMode
    }

    private static func map(_ freshness: ICloudDataFreshness) -> iCloudUsageReader.SyncStatus {
        switch freshness {
        case .waiting: return .waiting
        case .syncing: return .syncing
        case .stale(let date): return .stale(since: date)
        }
    }
}
