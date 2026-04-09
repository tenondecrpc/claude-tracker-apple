import Foundation
import WatchConnectivity

final class WatchSessionReceiver: NSObject, WCSessionDelegate {

    private let store: TokenStore

    init(store: TokenStore) {
        self.store = store
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - WCSessionDelegate

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        // No-op. We rely on didReceiveUserInfo updates.
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        applyUserInfo(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        // No-op — reachability changes don't affect transferUserInfo delivery.
    }

    private func applyUserInfo(_ userInfo: [String: Any]) {
        guard (userInfo["type"] as? String) == "UsageState" else { return }
        guard
            let utilization5h = userInfo["utilization5h"] as? Double,
            let utilization7d = userInfo["utilization7d"] as? Double,
            let resetAt5hInterval = userInfo["resetAt5h"] as? TimeInterval,
            let resetAt7dInterval = userInfo["resetAt7d"] as? TimeInterval,
            let isMocked = userInfo["isMocked"] as? Bool
        else { return }

        let state = UsageState(
            utilization5h: utilization5h,
            utilization7d: utilization7d,
            resetAt5h: Date(timeIntervalSince1970: resetAt5hInterval),
            resetAt7d: Date(timeIntervalSince1970: resetAt7dInterval),
            isMocked: isMocked,
            extraUsage: nil,
            isDoubleLimitPromoActive: nil
        )

        Task { @MainActor in
            self.store.apply(state)
        }
    }
}
