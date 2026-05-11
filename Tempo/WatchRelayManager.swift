import Foundation
import WatchConnectivity

// MARK: - WatchRelayManager (Tasks 5.1–5.4)

final class WatchRelayManager: NSObject {
    private struct PendingSessionTransfer {
        let sessionInfo: SessionInfo
        let alertPreferences: SessionAlertPreferences
        let appearanceMode: AppearanceMode
        /// The iOS `activeAccountId` captured when this session was queued.
        /// When the queue is flushed we re-check the current active account
        /// against `sessionInfo.accountId` and drop entries that no longer
        /// match, so a watch never gets a completion alert for an account
        /// the iPhone has since switched away from. `nil` means "do not
        /// filter by active account" - the same opt-out semantics
        /// `sendSession` uses when its caller cannot resolve an active
        /// account id.
        let activeAccountId: String?
        let accountLabel: String
    }

    private enum DefaultsKey {
        static let lastRelayedSessionID = "watchrelay.lastRelayedSessionID"
    }

    private let session = WCSession.default
    private let defaults = UserDefaults.standard
    private var didAssignDelegate = false
    private var pendingState: UsageState?
    private var pendingHistory: [UsageHistorySnapshot] = []
    private var pendingAlertPreferences: SessionAlertPreferences = .default
    private var pendingAppearanceMode: AppearanceMode?
    private var pendingAccountLabel: String = ""
    /// When true, a `NoActiveAccount` context send is queued and will be
    /// flushed after activation / pairing / watch-app-install. The last
    /// intent between `send(_:)` and `sendNoActiveAccount()` wins: sending
    /// a fresh UsageState clears this, and vice versa, matching the
    /// "replace current state" semantics of `updateApplicationContext`.
    private var pendingNoActiveAccount: Bool = false
    private var pendingSessions: [PendingSessionTransfer] = []
    private var hasRequestedActivation = false
    private var hasLoggedMissingWatchApp = false

    /// Called on arbitrary queue when paired/installed state changes.
    var onWatchStateChange: ((_ isPaired: Bool, _ isWatchAppInstalled: Bool) -> Void)?

    /// Called when the watch sends a `RequestFreshRelay` message via
    /// `sendMessage`. The iPhone should restart its iCloud reader and
    /// re-relay the active account's usage state.
    var onFreshRelayRequested: (() -> Void)?

    // MARK: - Activation (Task 5.2)

    func activate() {
        guard WCSession.isSupported() else { return }
        ensureDelegate()
        guard session.activationState != .activated else { return }
        guard !hasRequestedActivation else { return }
        hasRequestedActivation = true
        session.activate()
    }

    private func ensureDelegate() {
        if !didAssignDelegate {
            session.delegate = self
            didAssignDelegate = true
        }
    }

    // MARK: - Send UsageState (Task 5.4)

    func send(
        _ state: UsageState,
        history: [UsageHistorySnapshot] = [],
        alertPreferences: SessionAlertPreferences = .default,
        appearanceMode: AppearanceMode = .dark,
        accountLabel: String = ""
    ) {
        ensureDelegate()
        // Sending a real UsageState supersedes any pending "no active
        // account" context: the watch should render the newest payload.
        pendingNoActiveAccount = false
        guard session.activationState == .activated else {
            pendingState = state
            pendingHistory = history
            pendingAlertPreferences = alertPreferences
            pendingAppearanceMode = appearanceMode
            pendingAccountLabel = accountLabel
            activate()
            return
        }

        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled

        guard isPaired else {
            pendingState = state
            pendingHistory = history
            pendingAlertPreferences = alertPreferences
            pendingAppearanceMode = appearanceMode
            pendingAccountLabel = accountLabel
            return
        }

        guard isWatchAppInstalled else {
            pendingState = state
            pendingHistory = history
            pendingAlertPreferences = alertPreferences
            pendingAppearanceMode = appearanceMode
            pendingAccountLabel = accountLabel
            // Fallback path: some setups report watchInstalled=false while the watch app is running.
            // Queue a background transfer so the watch can still receive the latest state.
            enqueueLatestUsagePayload(
                state.toUserInfo(
                    history: history,
                    alertPreferences: alertPreferences,
                    appearanceMode: appearanceMode,
                    accountLabel: accountLabel
                )
            )
            if !hasLoggedMissingWatchApp {
                hasLoggedMissingWatchApp = true
            }
            return
        }

        hasLoggedMissingWatchApp = false

        let payload = state.toUserInfo(
            history: history,
            alertPreferences: alertPreferences,
            appearanceMode: appearanceMode,
            accountLabel: accountLabel
        )
        do {
            try session.updateApplicationContext(payload)
        } catch {
            enqueueLatestUsagePayload(payload)
        }
    }

    private func enqueueLatestUsagePayload(_ payload: [String: Any]) {
        session.outstandingUserInfoTransfers
            .filter { ($0.userInfo["type"] as? String) == "UsageState" }
            .forEach { $0.cancel() }
        session.transferUserInfo(payload)
    }

    private func flushPendingStateIfPossible() {
        guard let state = pendingState else { return }
        pendingState = nil
        let history = pendingHistory
        pendingHistory = []
        let alertPreferences = pendingAlertPreferences
        let appearanceMode = pendingAppearanceMode ?? .dark
        let accountLabel = pendingAccountLabel
        pendingAccountLabel = ""
        send(
            state,
            history: history,
            alertPreferences: alertPreferences,
            appearanceMode: appearanceMode,
            accountLabel: accountLabel
        )
    }

    // MARK: - Send NoActiveAccount (Task 5.4)

    /// Tells the watch that the iPhone currently has no active account,
    /// so the watch dashboard should clear any per-account state and
    /// render the "No accounts available" placeholder (see task 7.x).
    ///
    /// Uses `updateApplicationContext` rather than `transferUserInfo`
    /// because this is the replace-current-state channel: per design.md,
    /// "iPhone's `activeAccountId` is the single source of truth for the
    /// watch [and] updateApplicationContext [is used] with the new
    /// `accountId`...". `transferUserInfo` is reserved for durable
    /// session events that must still be delivered after a context
    /// has been superseded.
    ///
    /// Follows the same activation/pairing/install gating as `send(_:)`.
    /// When the session is not yet ready, the intent is queued via
    /// `pendingNoActiveAccount`; any subsequent `send(_:)` supersedes it.
    func sendNoActiveAccount() {
        ensureDelegate()
        // Clear any pending UsageState; the caller wants the watch to
        // show the empty-account state, not the previous account's data.
        pendingState = nil
        pendingHistory = []
        pendingAccountLabel = ""
        guard session.activationState == .activated else {
            pendingNoActiveAccount = true
            activate()
            return
        }
        guard session.isPaired, session.isWatchAppInstalled else {
            pendingNoActiveAccount = true
            return
        }

        let payload: [String: Any] = ["type": "NoActiveAccount"]
        do {
            try session.updateApplicationContext(payload)
            pendingNoActiveAccount = false
        } catch {
            // Unlike UsageState we do not fall back to transferUserInfo:
            // NoActiveAccount is a pure state-replacement signal and
            // isn't valuable as a durable event. Keep it queued; the
            // next watch-state change or activation will retry.
            pendingNoActiveAccount = true
        }
    }

    private func flushPendingNoActiveAccountIfPossible() {
        guard pendingNoActiveAccount else { return }
        sendNoActiveAccount()
    }

    func sendAppearanceMode(_ appearanceMode: AppearanceMode) {
        ensureDelegate()
        guard session.activationState == .activated else {
            pendingAppearanceMode = appearanceMode
            activate()
            return
        }

        guard session.isPaired, session.isWatchAppInstalled else {
            pendingAppearanceMode = appearanceMode
            return
        }

        session.transferUserInfo([
            "type": "AppearanceMode",
            "appearanceMode": appearanceMode.rawValue,
        ])
        pendingAppearanceMode = nil
    }

    private func flushPendingAppearanceModeIfPossible() {
        guard let pendingAppearanceMode else { return }
        sendAppearanceMode(pendingAppearanceMode)
    }

    // MARK: - Send SessionInfo

    /// Sends a `SessionInfo` completion payload to the watch via
    /// `transferUserInfo` (durable delivery channel), gating the send on
    /// the iPhone's active account.
    ///
    /// When `activeAccountId` is non-`nil`, the relay compares it to
    /// `sessionInfo.accountId`. If they differ we skip the transfer, do
    /// NOT update `lastRelayedSessionID`, and do not enqueue a pending
    /// retry: the session belongs to an account the iPhone is not
    /// currently relaying, and if the user later switches to that
    /// account the session will be re-evaluated fresh. Passing
    /// `activeAccountId: nil` opts out of gating so tests and future
    /// callers that do not have an active-account concept still work.
    ///
    /// The `accountLabel` piggybacks on the payload so the watch's
    /// `CompletionView` can display which account completed (task 7.4).
    /// We intentionally use a mutable default to stay source-compatible
    /// with the legacy call sites in `flushPendingSessionsIfPossible`.
    func sendSession(
        _ sessionInfo: SessionInfo,
        alertPreferences: SessionAlertPreferences = .default,
        appearanceMode: AppearanceMode = .dark,
        activeAccountId: String? = nil,
        accountLabel: String = ""
    ) {
        if let activeAccountId, sessionInfo.accountId != activeAccountId {
            // Per design.md the watch only ever renders the iPhone's
            // active account. Dropping the transfer here also avoids
            // consuming the dedup slot (`lastRelayedSessionID`), so if
            // the user later sets this session's account active, the
            // caller re-invokes `sendSession` and delivery proceeds.
            DevLog.trace(
                "AlertTrace",
                "Skipped SessionInfo because accountId=\(sessionInfo.accountId) does not match activeAccountId=\(activeAccountId)"
            )
            return
        }
        if lastRelayedSessionID == sessionInfo.sessionId {
            return
        }
        ensureDelegate()
        guard session.activationState == .activated else {
            enqueuePendingSessionIfNeeded(
                sessionInfo,
                alertPreferences: alertPreferences,
                appearanceMode: appearanceMode,
                activeAccountId: activeAccountId,
                accountLabel: accountLabel
            )
            activate()
            return
        }

        guard session.isPaired, session.isWatchAppInstalled else {
            enqueuePendingSessionIfNeeded(
                sessionInfo,
                alertPreferences: alertPreferences,
                appearanceMode: appearanceMode,
                activeAccountId: activeAccountId,
                accountLabel: accountLabel
            )
            return
        }

        session.transferUserInfo(
            sessionInfo.toUserInfo(
                alertPreferences: alertPreferences,
                appearanceMode: appearanceMode,
                accountLabel: accountLabel
            )
        )
        lastRelayedSessionID = sessionInfo.sessionId
    }

    private func flushPendingSessionsIfPossible() {
        guard !pendingSessions.isEmpty else { return }
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }

        let queued = pendingSessions
        pendingSessions.removeAll(keepingCapacity: true)
        queued.forEach { pending in
            // Re-check the captured active-account gate at flush time.
            // If the iPhone switched accounts while the session sat in
            // the queue, we drop the stale entry rather than deliver a
            // completion for an account the user is no longer viewing.
            if let expected = pending.activeAccountId,
               pending.sessionInfo.accountId != expected {
                DevLog.trace(
                    "AlertTrace",
                    "Skipped SessionInfo because accountId=\(pending.sessionInfo.accountId) does not match activeAccountId=\(expected)"
                )
                return
            }
            session.transferUserInfo(
                pending.sessionInfo.toUserInfo(
                    alertPreferences: pending.alertPreferences,
                    appearanceMode: pending.appearanceMode,
                    accountLabel: pending.accountLabel
                )
            )
            lastRelayedSessionID = pending.sessionInfo.sessionId
        }
    }

    private func enqueuePendingSessionIfNeeded(
        _ sessionInfo: SessionInfo,
        alertPreferences: SessionAlertPreferences,
        appearanceMode: AppearanceMode,
        activeAccountId: String?,
        accountLabel: String
    ) {
        guard pendingSessions.contains(where: { $0.sessionInfo.sessionId == sessionInfo.sessionId }) == false else { return }
        pendingSessions.append(
            PendingSessionTransfer(
                sessionInfo: sessionInfo,
                alertPreferences: alertPreferences,
                appearanceMode: appearanceMode,
                activeAccountId: activeAccountId,
                accountLabel: accountLabel
            )
        )
    }

    private var lastRelayedSessionID: String? {
        get { defaults.string(forKey: DefaultsKey.lastRelayedSessionID) }
        set { defaults.setValue(newValue, forKey: DefaultsKey.lastRelayedSessionID) }
    }
}

// MARK: - WCSessionDelegate (Task 5.3)

extension WatchRelayManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        hasRequestedActivation = (activationState == .activated)
        onWatchStateChange?(session.isPaired, session.isWatchAppInstalled)
        // Activation complete; send latest pending state if we have one.
        flushPendingStateIfPossible()
        flushPendingNoActiveAccountIfPossible()
        flushPendingAppearanceModeIfPossible()
        flushPendingSessionsIfPossible()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // User is switching the paired Apple Watch. Stop sending during transition.
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Wait for the next outbound payload to trigger activation.
        hasRequestedActivation = false
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        if session.isWatchAppInstalled {
            hasLoggedMissingWatchApp = false
        }
        onWatchStateChange?(session.isPaired, session.isWatchAppInstalled)
        flushPendingStateIfPossible()
        flushPendingNoActiveAccountIfPossible()
        flushPendingAppearanceModeIfPossible()
        flushPendingSessionsIfPossible()
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let type = message["type"] as? String else {
            replyHandler(["ok": false, "reason": "missing type"])
            return
        }
        switch type {
        case "RequestFreshRelay":
            DevLog.trace(
                "AlertTrace",
                "WatchRelayManager received RequestFreshRelay from watch"
            )
            replyHandler(["ok": true])
            onFreshRelayRequested?()
        default:
            replyHandler(["ok": false, "reason": "unknown type"])
        }
    }
}

// MARK: - UsageState WatchConnectivity Encoding (Task 5.5)

extension UsageState {
    func toUserInfo(
        history: [UsageHistorySnapshot] = [],
        alertPreferences: SessionAlertPreferences = .default,
        appearanceMode: AppearanceMode = .dark,
        accountLabel: String = ""
    ) -> [String: Any] {
        var info: [String: Any] = [
            "type": "UsageState",
            "accountId": accountId,
            "accountLabel": accountLabel,
            "utilization5h": utilization5h,
            "utilization7d": utilization7d,
            "resetAt5h": resetAt5h.timeIntervalSince1970,
            "resetAt7d": resetAt7d.timeIntervalSince1970,
            "isMocked": isMocked,
            "watchAlertsEnabled": alertPreferences.watchAlertsEnabled,
            "appearanceMode": appearanceMode.rawValue,
        ]
        // Include last 7 days of history snapshots for the watch trend view
        let recent = history.filter { $0.date >= Date().addingTimeInterval(-7 * 24 * 3600) }
        if !recent.isEmpty, let data = try? JSONEncoder().encode(recent) {
            info["usageHistory"] = data
        }
        return info
    }
}

extension SessionInfo {
    func toUserInfo(
        alertPreferences: SessionAlertPreferences = .default,
        appearanceMode: AppearanceMode = .dark,
        accountLabel: String = ""
    ) -> [String: Any] {
        [
            "type": "SessionInfo",
            "sessionId": sessionId,
            "accountId": accountId,
            "accountLabel": accountLabel,
            "inputTokens": inputTokens,
            "outputTokens": outputTokens,
            "costUSD": costUSD,
            "durationSeconds": durationSeconds,
            "timestamp": timestamp.timeIntervalSince1970,
            "watchAlertsEnabled": alertPreferences.watchAlertsEnabled,
            "appearanceMode": appearanceMode.rawValue,
        ]
    }
}
