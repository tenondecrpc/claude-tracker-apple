import SwiftUI

// MARK: - AppCoordinator

/// Wires together iCloud read state, app UI store, and watch relay.
@MainActor
final class AppCoordinator {
    let iCloudReader: iCloudUsageReader
    let store: IOSAppStore
    let relay: WatchRelayManager
    let phoneAlertManager: PhoneAlertManager
    private var hasStartedPhoneAlerts = false

    init() {
        let iCloudReader = iCloudUsageReader()
        let store = IOSAppStore(iCloudReader: iCloudReader)
        let relay = WatchRelayManager()
        let phoneAlertManager = PhoneAlertManager()

        self.iCloudReader = iCloudReader
        self.store = store
        self.relay = relay
        self.phoneAlertManager = phoneAlertManager

        #if DEBUG
        print("[Tempo iOS] AppCoordinator init bundleID=\(Bundle.main.bundleIdentifier ?? "nil") iPhoneAlerts=\(store.iPhoneAlertsEnabled) watchAlerts=\(store.watchAlertsEnabled)")
        #endif
        DevLog.trace(
            "AlertTrace",
            "TempoApp coordinator init initialIPhoneAlerts=\(store.iPhoneAlertsEnabled) initialWatchAlerts=\(store.watchAlertsEnabled)"
        )

        iCloudReader.onUsageState = { [weak relay, weak iCloudReader, weak store] (state: UsageState) in
            #if DEBUG
            print("[Tempo iOS] received usage state utilization5h=\(state.utilization5h) utilization7d=\(state.utilization7d)")
            #endif
            DevLog.trace(
                "AlertTrace",
                "TempoApp received usage state utilization5h=\(state.utilization5h) utilization7d=\(state.utilization7d) historyCount=\(iCloudReader?.historySnapshots.count ?? 0)"
            )
            relay?.send(
                state,
                history: iCloudReader?.historySnapshots ?? [],
                alertPreferences: store?.sessionAlertPreferences ?? .default
            )
        }
        iCloudReader.onSessionInfo = { [weak relay, weak store, weak phoneAlertManager] (session: SessionInfo) in
            let preferences = store?.sessionAlertPreferences ?? .default
            #if DEBUG
            print(
                "[Tempo iOS] received synced session id=\(session.sessionId) iPhoneAlerts=\(preferences.iPhoneAlertsEnabled) watchAlerts=\(preferences.watchAlertsEnabled)"
            )
            #endif
            DevLog.trace(
                "AlertTrace",
                "TempoApp received synced session id=\(session.sessionId) iPhoneAlerts=\(preferences.iPhoneAlertsEnabled) watchAlerts=\(preferences.watchAlertsEnabled)"
            )
            phoneAlertManager?.notifySessionCompletion(
                for: session,
                enabledInPreferences: preferences.iPhoneAlertsEnabled
            )
            relay?.sendSession(session, alertPreferences: preferences)
        }
        iCloudReader.onAlertPreferences = { [weak store] preferences in
            #if DEBUG
            print(
                "[Tempo iOS] received synced alert preferences iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
            )
            #endif
            DevLog.trace(
                "AlertTrace",
                "TempoApp received synced alert preferences iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
            )
            Task { @MainActor in
                store?.applySyncedAlertPreferences(preferences)
            }
        }
        relay.onWatchStateChange = { [weak store] isPaired, isInstalled in
            Task { @MainActor in
                store?.updateWatchState(isPaired: isPaired, isInstalled: isInstalled)
            }
        }
        store.onSessionAlertPreferencesChange = { [weak relay, weak iCloudReader, weak phoneAlertManager] preferences in
            #if DEBUG
            print(
                "[Tempo iOS] local preference change iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
            )
            #endif
            DevLog.trace(
                "AlertTrace",
                "TempoApp local preference change iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
            )
            phoneAlertManager?.syncAuthorization(enabledInPreferences: preferences.iPhoneAlertsEnabled)
            if let state = iCloudReader?.latestUsage {
                relay?.send(state, history: iCloudReader?.historySnapshots ?? [], alertPreferences: preferences)
            }
            do {
                try AlertPreferencesSync.write(preferences)
            } catch {
                print("[AlertPreferences] failed to sync to iCloud: \(error.localizedDescription)")
            }
        }
        relay.activate()
        DevLog.trace("AlertTrace", "TempoApp requested WatchRelay activation")
        iCloudReader.start()
        DevLog.trace("AlertTrace", "TempoApp started iCloudUsageReader from coordinator init")
    }

    // MARK: - Lifecycle

    func onBecomeActive() {
        #if DEBUG
        print("[Tempo iOS] became active iPhoneAlerts=\(store.iPhoneAlertsEnabled) watchAlerts=\(store.watchAlertsEnabled)")
        #endif
        DevLog.trace(
            "AlertTrace",
            "TempoApp became active iPhoneAlerts=\(store.iPhoneAlertsEnabled) watchAlerts=\(store.watchAlertsEnabled)"
        )
        if hasStartedPhoneAlerts {
            phoneAlertManager.syncAuthorization(enabledInPreferences: store.iPhoneAlertsEnabled)
        } else {
            hasStartedPhoneAlerts = true
            phoneAlertManager.syncAuthorization(enabledInPreferences: store.iPhoneAlertsEnabled)
        }
        iCloudReader.restart()
        store.refreshStaleness()
    }
}

// MARK: - TempoApp

@main
struct TempoApp: App {
    @State private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(store: coordinator.store)
                .task {
                    #if DEBUG
                    print("[Tempo iOS] ContentView task scenePhase=\(String(describing: scenePhase))")
                    #endif
                    DevLog.trace("AlertTrace", "TempoApp ContentView task scenePhase=\(String(describing: scenePhase))")
                    if scenePhase == .active {
                        coordinator.onBecomeActive()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    #if DEBUG
                    print("[Tempo iOS] scenePhase changed to \(String(describing: phase))")
                    #endif
                    DevLog.trace("AlertTrace", "TempoApp scenePhase changed to \(String(describing: phase))")
                    if phase == .active {
                        coordinator.onBecomeActive()
                    }
                }
        }
    }
}
