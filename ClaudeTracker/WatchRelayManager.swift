import Foundation
import WatchConnectivity

// MARK: - WatchRelayManager (Tasks 5.1–5.4)

final class WatchRelayManager: NSObject {
    private enum DefaultsKey {
        static let lastRelayedSessionID = "watchrelay.lastRelayedSessionID"
    }

    private let session = WCSession.default
    private let defaults = UserDefaults.standard
    private var didAssignDelegate = false
    private var pendingState: UsageState?
    private var pendingHistory: [UsageHistorySnapshot] = []
    private var pendingSessions: [SessionInfo] = []
    private var hasRequestedActivation = false
    private var hasLoggedMissingWatchApp = false

    /// Called on arbitrary queue when paired/installed state changes.
    var onWatchStateChange: ((_ isPaired: Bool, _ isWatchAppInstalled: Bool) -> Void)?

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

    func send(_ state: UsageState, history: [UsageHistorySnapshot] = []) {
        ensureDelegate()
        guard session.activationState == .activated else {
            pendingState = state
            pendingHistory = history
            activate()
            return
        }

        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        let watchDir = session.watchDirectoryURL?.path ?? "nil"
        print("[WatchRelay] bundleID=\(Bundle.main.bundleIdentifier ?? "nil"), paired=\(isPaired), watchInstalled=\(isWatchAppInstalled), reachable=\(session.isReachable), watchDir=\(watchDir), isMocked=\(state.isMocked)")

        guard isPaired else {
            pendingState = state
            pendingHistory = history
            return
        }

        guard isWatchAppInstalled else {
            pendingState = state
            pendingHistory = history
            // Fallback path: some setups report watchInstalled=false while the watch app is running.
            // Queue a background transfer so the watch can still receive the latest state.
            enqueueLatestUsagePayload(state.toUserInfo(history: history))
            if !hasLoggedMissingWatchApp {
                hasLoggedMissingWatchApp = true
                print("[WatchRelay] watch counterpart app not installed on paired Apple Watch. Install the watch app, then the latest state will be sent automatically.")
            }
            return
        }

        hasLoggedMissingWatchApp = false

        let payload = state.toUserInfo(history: history)
        do {
            try session.updateApplicationContext(payload)
        } catch {
            print("[WatchRelay] updateApplicationContext failed: \(error)")
            enqueueLatestUsagePayload(payload)
        }
    }

    private func enqueueLatestUsagePayload(_ payload: [String: Any]) {
        session.outstandingUserInfoTransfers
            .filter { ($0.userInfo["type"] as? String) == "UsageState" }
            .forEach { $0.cancel() }
        session.transferUserInfo(payload)
        print("[WatchRelay] queued transferUserInfo fallback for UsageState")
    }

    private func flushPendingStateIfPossible() {
        guard let state = pendingState else { return }
        pendingState = nil
        let history = pendingHistory
        pendingHistory = []
        send(state, history: history)
    }

    // MARK: - Send SessionInfo

    func sendSession(_ sessionInfo: SessionInfo) {
        if lastRelayedSessionID == sessionInfo.sessionId {
            return
        }
        ensureDelegate()
        guard session.activationState == .activated else {
            enqueuePendingSessionIfNeeded(sessionInfo)
            activate()
            return
        }

        guard session.isPaired, session.isWatchAppInstalled else {
            enqueuePendingSessionIfNeeded(sessionInfo)
            return
        }

        session.transferUserInfo(sessionInfo.toUserInfo())
        lastRelayedSessionID = sessionInfo.sessionId
        print("[WatchRelay] queued transferUserInfo for SessionInfo id=\(sessionInfo.sessionId)")
    }

    private func flushPendingSessionsIfPossible() {
        guard !pendingSessions.isEmpty else { return }
        guard session.activationState == .activated else { return }
        guard session.isPaired, session.isWatchAppInstalled else { return }

        let queued = pendingSessions
        pendingSessions.removeAll(keepingCapacity: true)
        queued.forEach {
            session.transferUserInfo($0.toUserInfo())
            lastRelayedSessionID = $0.sessionId
        }
        print("[WatchRelay] flushed \(queued.count) queued SessionInfo payload(s)")
    }

    private func enqueuePendingSessionIfNeeded(_ sessionInfo: SessionInfo) {
        guard pendingSessions.contains(where: { $0.sessionId == sessionInfo.sessionId }) == false else { return }
        pendingSessions.append(sessionInfo)
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
        let watchDir = session.watchDirectoryURL?.path ?? "nil"
        print("[WatchRelay] activation: state=\(activationState.rawValue), paired=\(session.isPaired), watchInstalled=\(session.isWatchAppInstalled), reachable=\(session.isReachable), watchDir=\(watchDir), error=\(String(describing: error))")
        hasRequestedActivation = (activationState == .activated)
        onWatchStateChange?(session.isPaired, session.isWatchAppInstalled)
        // Activation complete; send latest pending state if we have one.
        flushPendingStateIfPossible()
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
        let watchDir = session.watchDirectoryURL?.path ?? "nil"
        print("[WatchRelay] watchStateChanged: paired=\(session.isPaired), watchInstalled=\(session.isWatchAppInstalled), reachable=\(session.isReachable), watchDir=\(watchDir)")
        if session.isWatchAppInstalled {
            hasLoggedMissingWatchApp = false
        }
        onWatchStateChange?(session.isPaired, session.isWatchAppInstalled)
        flushPendingStateIfPossible()
        flushPendingSessionsIfPossible()
    }
}

// MARK: - UsageState WatchConnectivity Encoding (Task 5.5)

extension UsageState {
    func toUserInfo(history: [UsageHistorySnapshot] = []) -> [String: Any] {
        var info: [String: Any] = [
            "type": "UsageState",
            "utilization5h": utilization5h,
            "utilization7d": utilization7d,
            "resetAt5h": resetAt5h.timeIntervalSince1970,
            "resetAt7d": resetAt7d.timeIntervalSince1970,
            "isMocked": isMocked,
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
    func toUserInfo() -> [String: Any] {
        [
            "type": "SessionInfo",
            "sessionId": sessionId,
            "inputTokens": inputTokens,
            "outputTokens": outputTokens,
            "costUSD": costUSD,
            "durationSeconds": durationSeconds,
            "timestamp": timestamp.timeIntervalSince1970,
        ]
    }
}
