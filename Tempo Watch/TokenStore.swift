import Observation
import Foundation

@Observable @MainActor
final class TokenStore {
    private(set) var sessions: [SessionInfo] = []
    var pendingCompletion: SessionInfo? = nil
    private(set) var usageState: UsageState = .mock
    private(set) var usageHistory: [UsageHistorySnapshot] = []
    private(set) var appearanceMode: AppearanceMode = .dark
    private(set) var areNotificationsEnabled = false
    private(set) var watchAlertsEnabledInPreferences = SessionAlertPreferences.default.watchAlertsEnabled
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
        // Drop any pending completion sheet that belonged to a different
        // account before we commit to the new `activeAccountId`. Per
        // design.md "Watch UX" the completion sheet must only fire for the
        // currently active account; showing a stale sheet after an account
        // switch would surface the wrong account label and cost figures.
        clearPendingCompletionIfStale(newAccountId: state.accountId)
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
        // Same rationale as `apply(_:)`: if the iPhone has relayed a new
        // accountId while an older account's completion sheet is still
        // pending, clear it so the dashboard does not show a cross-account
        // banner after the switch.
        clearPendingCompletionIfStale(newAccountId: id)
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
        pendingCompletion = nil
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

    /// Drop `pendingCompletion` when it belongs to a different account than
    /// the one the iPhone is about to make active. The completion sheet is
    /// surfaced from `TempoWatchApp` by observing `pendingCompletion`, so
    /// clearing it here is what prevents a stale sheet from popping after
    /// an account switch. Called from `apply(_:)` and
    /// `applyActiveAccount(id:label:)` where we have an authoritative new
    /// accountId. A nil or empty `newAccountId` is a no-op so mid-launch
    /// transitions do not accidentally erase a valid pending session.
    private func clearPendingCompletionIfStale(newAccountId: String) {
        guard !newAccountId.isEmpty else { return }
        guard let pending = pendingCompletion else { return }
        if pending.accountId != newAccountId {
            DevLog.trace(
                "AlertTrace",
                "Clearing stale pendingCompletion: pending accountId=\(pending.accountId) != new=\(newAccountId)"
            )
            pendingCompletion = nil
        }
    }

    func applyHistory(_ snapshots: [UsageHistorySnapshot]) {
        usageHistory = snapshots
    }

    func applySession(_ session: SessionInfo) {
        sessions.removeAll { $0.sessionId == session.sessionId }
        sessions.append(session)
        sessions.sort { $0.timestamp < $1.timestamp }
        // Gate `pendingCompletion` on the currently active account. Per
        // design.md "Watch UX" the completion sheet must only fire for the
        // account the iPhone is currently relaying. If the incoming session
        // belongs to a different account, keep it in `sessions` (history
        // stays correct) but do not raise the sheet. The receiver is also
        // responsible for the outer ignore in task 7.4; this is the inner
        // safety net so the sheet can never render cross-account.
        if let active = activeAccountId, !active.isEmpty, session.accountId != active {
            DevLog.trace(
                "AlertTrace",
                "Skipping pendingCompletion: session accountId=\(session.accountId) != active=\(active)"
            )
            return
        }
        pendingCompletion = session
    }

    func applyAppearanceMode(_ appearanceMode: AppearanceMode) {
        self.appearanceMode = appearanceMode
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        areNotificationsEnabled = enabled
    }

    func setWatchAlertsEnabledInPreferences(_ enabled: Bool) {
        watchAlertsEnabledInPreferences = enabled
    }
}
