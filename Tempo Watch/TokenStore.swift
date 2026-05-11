import Observation
import Foundation

@Observable @MainActor
final class TokenStore {
    private(set) var sessions: [SessionInfo] = []
    private(set) var usageState: UsageState = .mock
    private(set) var usageHistory: [UsageHistorySnapshot] = []
    private(set) var appearanceMode: AppearanceMode = .dark
    /// Canonical `accountId` most recently relayed from the iPhone via
    /// `updateApplicationContext`. `nil` means the watch has not yet received
    /// any account context in this process lifetime, or the iPhone has
    /// signalled that no active account is currently selected (see
    /// `hasNoActiveAccount`).
    private(set) var activeAccountId: String? = nil
    /// Human-readable label for the active account (typically the email
    /// address or a user-set display name). Empty string when unknown or
    /// cleared by `applyNoActiveAccount()`.
    private(set) var accountLabel: String = ""
    /// `true` when the iPhone has relayed a `NoActiveAccount` context,
    /// signalling that no account is currently active and the watch should
    /// render the "No accounts available" placeholder rather than stale
    /// usage data. Cleared whenever a fresh `UsageState` arrives.
    private(set) var hasNoActiveAccount: Bool = false

    /// Timestamp of the most recent `UsageState` application from any
    /// WatchConnectivity relay. Drives the "Updated Xm ago" freshness
    /// indicator on the dashboard and the refresh coordinator's success
    /// detection (it observes this value to know when a fresh relay
    /// has arrived after sending `RequestFreshRelay`).
    private(set) var lastRelayReceivedAt: Date? = nil

    /// Returns `lastRelayReceivedAt` only when the watch has an active
    /// account and is not in the `NoActiveAccount` state. Used by the
    /// dashboard freshness label to avoid showing stale timestamps
    /// from a previous account.
    var lastRelayReceivedAtForActiveAccount: Date? {
        guard !hasNoActiveAccount else { return nil }
        guard activeAccountId != nil else { return nil }
        return lastRelayReceivedAt
    }

    var lastSession: SessionInfo? {
        sessions.max(by: { $0.timestamp < $1.timestamp })
    }

    init() {
        if let rawAppearanceMode = UserDefaults(suiteName: TempoWatchShared.appGroupIdentifier)?
            .string(forKey: TempoWatchShared.appearanceModeKey),
           let parsedAppearanceMode = AppearanceMode(rawValue: rawAppearanceMode) {
            appearanceMode = parsedAppearanceMode
        }
    }

    func apply(_ state: UsageState) {
        usageState = state
        activeAccountId = state.accountId
        lastRelayReceivedAt = Date()
        // Receiving a UsageState supersedes any prior "no active account"
        // signal per design.md: the watch renders whatever the iPhone
        // currently relays.
        hasNoActiveAccount = false
    }

    /// Record the account label shipped alongside `UsageState` / `SessionInfo`
    /// payloads. The receiver passes this through without interpretation so
    /// the dashboard header (see task 7.3) can render it.
    func applyActiveAccount(id: String, label: String) {
        activeAccountId = id
        accountLabel = label
        hasNoActiveAccount = false
    }

    /// Clears per-account state when the iPhone signals no active account.
    /// Called from `WatchSessionReceiver.applyNoActiveAccount()` on the main
    /// actor. Per design.md the watch renders a "No accounts available"
    /// state in this case and must not keep showing the last account's
    /// usage, pending completion, or label.
    func applyNoActiveAccount() {
        activeAccountId = nil
        accountLabel = ""
        usageState = Self.emptyUsageState
        usageHistory = []
        hasNoActiveAccount = true
    }

    /// Zeroed `UsageState` used when the iPhone has no active account. The
    /// dashboard branches on `hasNoActiveAccount` before rendering any of
    /// these fields (task 7.3), but we still pick a neutral value so any
    /// stray reader does not flash stale data from the previous account.
    private static let emptyUsageState = UsageState(
        accountId: AccountIdentifier.unassignedAccountId,
        utilization5h: 0,
        utilization7d: 0,
        resetAt5h: Date(timeIntervalSince1970: 0),
        resetAt7d: Date(timeIntervalSince1970: 0),
        isMocked: false,
        extraUsage: nil,
        isDoubleLimitPromoActive: nil
    )

    func applyHistory(_ snapshots: [UsageHistorySnapshot]) {
        usageHistory = snapshots
    }

    func applySession(_ session: SessionInfo) {
        sessions.removeAll { $0.sessionId == session.sessionId }
        sessions.append(session)
        sessions.sort { $0.timestamp < $1.timestamp }
    }

    func applyAppearanceMode(_ appearanceMode: AppearanceMode) {
        self.appearanceMode = appearanceMode
    }
}
