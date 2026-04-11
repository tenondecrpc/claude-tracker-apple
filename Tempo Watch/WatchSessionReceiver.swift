import Foundation
import WatchConnectivity
import WidgetKit

final class WatchSessionReceiver: NSObject, WCSessionDelegate {

    private let store: TokenStore
    private let alertManager: WatchAlertManager

    init(store: TokenStore, alertManager: WatchAlertManager) {
        self.store = store
        self.alertManager = alertManager
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
        // Apply any context already delivered before this launch
        let ctx = session.receivedApplicationContext
        if !ctx.isEmpty {
            applyUserInfo(ctx)
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        applyUserInfo(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        applyUserInfo(userInfo)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {}

    private func applyUserInfo(_ userInfo: [String: Any]) {
        guard let payloadType = userInfo["type"] as? String else { return }
        switch payloadType {
        case "UsageState":
            applyUsageState(userInfo)
        case "SessionInfo":
            applySessionInfo(userInfo)
        default:
            return
        }
    }

    private func applyUsageState(_ userInfo: [String: Any]) {
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

        let watchAlertsEnabled = userInfo["watchAlertsEnabled"] as? Bool ?? SessionAlertPreferences.default.watchAlertsEnabled

        var snapshots: [UsageHistorySnapshot]? = nil
        if let historyData = userInfo["usageHistory"] as? Data {
            snapshots = try? JSONDecoder().decode([UsageHistorySnapshot].self, from: historyData)
        }

        let appGroupID = "group.com.tenondecrpc.tempo.watch"
        UserDefaults(suiteName: appGroupID)?.set(utilization5h, forKey: "complication_utilization5h")
        WidgetCenter.shared.reloadAllTimelines()

        Task { @MainActor in
            self.store.apply(state)
            self.store.setWatchAlertsEnabledInPreferences(watchAlertsEnabled)
            if let snapshots {
                self.store.applyHistory(snapshots)
            }
        }
        alertManager.refreshAlertState(enabledInPreferences: watchAlertsEnabled)
    }

    private func applySessionInfo(_ userInfo: [String: Any]) {
        guard
            let sessionId = userInfo["sessionId"] as? String,
            let inputTokens = userInfo["inputTokens"] as? Int,
            let outputTokens = userInfo["outputTokens"] as? Int,
            let costUSD = userInfo["costUSD"] as? Double,
            let durationSeconds = userInfo["durationSeconds"] as? Int,
            let timestampInterval = userInfo["timestamp"] as? TimeInterval
        else { return }

        let watchAlertsEnabled = userInfo["watchAlertsEnabled"] as? Bool ?? SessionAlertPreferences.default.watchAlertsEnabled

        let sessionInfo = SessionInfo(
            sessionId: sessionId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: costUSD,
            durationSeconds: durationSeconds,
            timestamp: Date(timeIntervalSince1970: timestampInterval)
        )

        Task { @MainActor in
            self.store.applySession(sessionInfo)
            self.store.setWatchAlertsEnabledInPreferences(watchAlertsEnabled)
        }
        alertManager.notifySessionCompletion(
            for: sessionInfo,
            enabledInPreferences: watchAlertsEnabled
        )
    }
}
