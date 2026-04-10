import Foundation
import WatchConnectivity
import WidgetKit

final class WatchSessionReceiver: NSObject, WCSessionDelegate {

    private let store: TokenStore

    init(store: TokenStore) {
        self.store = store
        super.init()
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        let companionID = Bundle.main.object(forInfoDictionaryKey: "WKCompanionAppBundleIdentifier") as? String ?? "nil"
        print("[WCSession] watchBundleID=\(bundleID), WKCompanionAppBundleIdentifier=\(companionID)")
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
        print("[WCSession] activation: \(activationState.rawValue), companionInstalled: \(session.isCompanionAppInstalled), error: \(String(describing: error))")
        // Apply any context already delivered before this launch
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty {
            print("[WCSession] applying receivedApplicationContext on activation")
            applyUserInfo(ctx)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("[WCSession] didReceiveApplicationContext keys: \(applicationContext.keys.sorted())")
        applyUserInfo(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        print("[WCSession] didReceiveUserInfo keys: \(userInfo.keys.sorted())")
        applyUserInfo(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WCSession] reachabilityChanged: \(WCSession.default.isReachable)")
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

        var snapshots: [UsageHistorySnapshot]? = nil
        if let historyData = userInfo["usageHistory"] as? Data {
            snapshots = try? JSONDecoder().decode([UsageHistorySnapshot].self, from: historyData)
        }

        let appGroupID = "group.com.tenondecrpc.claudetracker.watch"
        UserDefaults(suiteName: appGroupID)?.set(utilization5h, forKey: "complication_utilization5h")
        WidgetCenter.shared.reloadAllTimelines()

        Task { @MainActor in
            self.store.apply(state)
            if let snapshots {
                self.store.applyHistory(snapshots)
            }
        }
    }
}
