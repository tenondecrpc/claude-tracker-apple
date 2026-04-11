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
    private var hasStartedAlerts = false

    init() {
        let store = TokenStore()
        let alertManager = WatchAlertManager()
        let receiver = WatchSessionReceiver(store: store, alertManager: alertManager)

        self.store = store
        self.alertManager = alertManager
        self.receiver = receiver

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
    }
}

@main
struct Tempo_WatchApp: App {
    @State private var coordinator = WatchAppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(coordinator.store)
                .task {
                    coordinator.onScenePhaseChange(scenePhase)
                }
                .onChange(of: scenePhase) { _, phase in
                    coordinator.onScenePhaseChange(phase)
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
