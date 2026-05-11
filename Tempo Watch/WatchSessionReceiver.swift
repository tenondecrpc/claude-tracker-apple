import Foundation
import WatchConnectivity
import WidgetKit

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
        case "AppearanceMode":
            applyAppearanceMode(userInfo)
        case "NoActiveAccount":
            applyNoActiveAccount()
        default:
            return
        }
    }

    private func applyUsageState(_ userInfo: [String: Any]) {
        // accountId is required: per design.md, `UsageState` decoding on the
        // watch must not silently fall back to an `unassigned` bucket. If the
        // iPhone forgets to include the field we log and drop the payload
        // rather than synthesize a partial state.
        guard let accountId = userInfo["accountId"] as? String, !accountId.isEmpty else {
            DevLog.trace(
                "AlertTrace",
                "Dropped UsageState payload on watch: missing accountId"
            )
            return
        }
        guard
            let utilization5h = userInfo["utilization5h"] as? Double,
            let utilization7d = userInfo["utilization7d"] as? Double,
            let resetAt5hInterval = userInfo["resetAt5h"] as? TimeInterval,
            let resetAt7dInterval = userInfo["resetAt7d"] as? TimeInterval,
            let isMocked = userInfo["isMocked"] as? Bool
        else { return }

        let accountLabel = userInfo["accountLabel"] as? String ?? ""

        let state = UsageState(
            accountId: accountId,
            utilization5h: utilization5h,
            utilization7d: utilization7d,
            resetAt5h: Date(timeIntervalSince1970: resetAt5hInterval),
            resetAt7d: Date(timeIntervalSince1970: resetAt7dInterval),
            isMocked: isMocked,
            extraUsage: nil,
            isDoubleLimitPromoActive: nil
        )

        let appearanceMode = Self.appearanceMode(from: userInfo)

        var snapshots: [UsageHistorySnapshot]? = nil
        if let historyData = userInfo["usageHistory"] as? Data {
            snapshots = try? JSONDecoder().decode([UsageHistorySnapshot].self, from: historyData)
        }

        let watchDefaults = UserDefaults(suiteName: TempoWatchShared.appGroupIdentifier)
        watchDefaults?.set(utilization5h, forKey: TempoWatchShared.complicationUtilization5hKey)
        watchDefaults?.set(appearanceMode.rawValue, forKey: TempoWatchShared.appearanceModeKey)
        WidgetCenter.shared.reloadAllTimelines()

        Task { @MainActor in
            self.store.apply(state)
            self.store.applyActiveAccount(id: accountId, label: accountLabel)
            self.store.applyAppearanceMode(appearanceMode)
            if let snapshots {
                self.store.applyHistory(snapshots)
            }
        }
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

        // accountId on SessionInfo is allowed to be absent (CLI-only /
        // legacy payloads) per the shared model contract; default to the
        // unassigned bucket rather than dropping the payload. CLI-only
        // sessions are intentionally allowed to surface on whichever active
        // account the watch is currently following (the iPhone gates real
        // account-owned completions in `WatchRelayManager`; the unassigned
        // bucket is a shared "no account" lane that every active account
        // should still see).
        let accountId = userInfo["accountId"] as? String ?? AccountIdentifier.unassignedAccountId
        let accountLabel = userInfo["accountLabel"] as? String ?? ""

        let appearanceMode = Self.appearanceMode(from: userInfo)

        let sessionInfo = SessionInfo(
            sessionId: sessionId,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            costUSD: costUSD,
            durationSeconds: durationSeconds,
            timestamp: Date(timeIntervalSince1970: timestampInterval),
            accountId: accountId
        )

        // Task 7.4: outer receiver-level safety net for mismatched
        // accountIds. A SessionInfo for a non-active account should never
        // have side effects on the watch at all: no `sessions` history
        // mutation. Exception: `unassigned` (CLI-only) sessions are always
        // allowed through because they have no owning account.
        Task { @MainActor in
            let isUnassigned = accountId == AccountIdentifier.unassignedAccountId
            if !isUnassigned,
               let active = self.store.activeAccountId,
               !active.isEmpty,
               active != accountId {
                DevLog.trace(
                    "AlertTrace",
                    "Dropped SessionInfo: session accountId=\(accountId) does not match activeAccountId=\(active)"
                )
                self.store.applyAppearanceMode(appearanceMode)
                return
            }

            self.store.applySession(sessionInfo)
            if !accountLabel.isEmpty {
                self.store.applyActiveAccount(id: accountId, label: accountLabel)
            }
            self.store.applyAppearanceMode(appearanceMode)
        }
    }

    private func applyAppearanceMode(_ userInfo: [String: Any]) {
        let appearanceMode = Self.appearanceMode(from: userInfo)
        let watchDefaults = UserDefaults(suiteName: TempoWatchShared.appGroupIdentifier)
        watchDefaults?.set(appearanceMode.rawValue, forKey: TempoWatchShared.appearanceModeKey)
        WidgetCenter.shared.reloadAllTimelines()

        Task { @MainActor in
            self.store.applyAppearanceMode(appearanceMode)
        }
    }

    /// Handles the `NoActiveAccount` context sent by the iPhone when it has
    /// no active account selected. Clears usage, pending completion, and
    /// account label on the main actor so the dashboard (task 7.3) can
    /// render the "No accounts available" placeholder without flashing
    /// stale data from the previous account.
    private func applyNoActiveAccount() {
        Task { @MainActor in
            self.store.applyNoActiveAccount()
        }
    }

    private static func appearanceMode(from userInfo: [String: Any]) -> AppearanceMode {
        if let rawValue = userInfo["appearanceMode"] as? String,
           let appearanceMode = AppearanceMode(rawValue: rawValue) {
            return appearanceMode
        }
        return .dark
    }
}
