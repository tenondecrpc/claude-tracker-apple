//
//  Tempo_WatchApp.swift
//  Tempo Watch App
//
//  Created by Cristian Paniagua on 27/03/2026.
//

import SwiftUI

@MainActor
final class WatchAppCoordinator {
    let store: TokenStore
    let alertManager: WatchAlertManager
    let receiver: WatchSessionReceiver
    let refreshCoordinator: WatchRefreshCoordinator
    private var hasStartedAlerts = false

    init() {
        let store = TokenStore()
        let alertManager = WatchAlertManager()
        let receiver = WatchSessionReceiver(store: store, alertManager: alertManager)
        let refreshCoordinator = WatchRefreshCoordinator(store: store)

        self.store = store
        self.alertManager = alertManager
        self.receiver = receiver
        self.refreshCoordinator = refreshCoordinator

        alertManager.onAlertStateChange = { [weak store] enabled in
            Task { @MainActor in
                store?.setNotificationsEnabled(enabled)
            }
        }
    }

    func onScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }
        if hasStartedAlerts {
            alertManager.refreshAlertState(enabledInPreferences: store.watchAlertsEnabledInPreferences)
        } else {
            hasStartedAlerts = true
            alertManager.syncAuthorization(enabledInPreferences: store.watchAlertsEnabledInPreferences)
        }

        // Request fresh data from iPhone on foreground activation.
        // Per spec scenario "Scene becomes active without account":
        // do NOT request when activeAccountId is nil or hasNoActiveAccount.
        if store.activeAccountId != nil, !store.hasNoActiveAccount {
            refreshCoordinator.requestRefresh()
        }
    }
}

@main
struct Tempo_WatchApp: App {
    @State private var coordinator = WatchAppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .applyClaudeAppearance(coordinator.store.appearanceMode)
                .environment(coordinator.store)
                .environment(coordinator.refreshCoordinator)
                .task {
                    coordinator.onScenePhaseChange(scenePhase)
                }
                .onChange(of: scenePhase) { _, phase in
                    coordinator.onScenePhaseChange(phase)
                }
                .onChange(of: coordinator.store.lastRelayReceivedAt) { _, _ in
                    coordinator.refreshCoordinator.checkForFreshRelay()
                }
        }
    }
}

struct RootView: View {
    @Environment(TokenStore.self) private var store

    var body: some View {
        @Bindable var bindableStore = store
        TabView {
            ContentView()
                .tag(0)
            TrendView()
                .tag(1)
            SessionView()
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
        .sheet(item: $bindableStore.pendingCompletion) { (item: SessionInfo) in
            CompletionView(session: item)
        }
    }
}
