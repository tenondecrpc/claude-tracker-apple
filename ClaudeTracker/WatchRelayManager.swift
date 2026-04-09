import Foundation
import WatchConnectivity

// MARK: - WatchRelayManager (Tasks 5.1–5.4)

final class WatchRelayManager: NSObject {
    private let session = WCSession.default
    private var didAssignDelegate = false
    private var pendingState: UsageState?
    private var hasRequestedActivation = false

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

    func send(_ state: UsageState) {
        ensureDelegate()
        guard session.activationState == .activated else {
            pendingState = state
            activate()
            return
        }

        // Cancel stale UsageState transfers before enqueueing a new one.
        // This prevents a burst of outdated snapshots when the watch reconnects.
        // NOTE: Never cancel SessionInfo transfers — every session event must be delivered.
        session.outstandingUserInfoTransfers
            .filter { ($0.userInfo["type"] as? String) == "UsageState" }
            .forEach { $0.cancel() }
        session.transferUserInfo(state.toUserInfo())
    }

    private func flushPendingStateIfPossible() {
        guard let state = pendingState else { return }
        pendingState = nil
        send(state)
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
        // Activation complete; send latest pending state if we have one.
        flushPendingStateIfPossible()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // User is switching the paired Apple Watch. Stop sending during transition.
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Wait for the next outbound payload to trigger activation.
        hasRequestedActivation = false
    }
}

// MARK: - UsageState WatchConnectivity Encoding (Task 5.5)

extension UsageState {
    func toUserInfo() -> [String: Any] {
        [
            "type": "UsageState",
            "utilization5h": utilization5h,
            "utilization7d": utilization7d,
            "resetAt5h": resetAt5h.timeIntervalSince1970,
            "resetAt7d": resetAt7d.timeIntervalSince1970,
            "isMocked": isMocked,
        ]
    }
}
