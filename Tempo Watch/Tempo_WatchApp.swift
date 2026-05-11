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
    let receiver: WatchSessionReceiver
    let refreshCoordinator: WatchRefreshCoordinator

    init() {
        let store = TokenStore()
        let receiver = WatchSessionReceiver(store: store)
        let refreshCoordinator = WatchRefreshCoordinator(store: store)

        self.store = store
        self.receiver = receiver
        self.refreshCoordinator = refreshCoordinator
    }

    func onScenePhaseChange(_ phase: ScenePhase) {
        guard phase == .active else { return }

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
        TabView {
            ContentView()
                .tag(0)
            TrendView()
                .tag(1)
            SessionView()
                .tag(2)
        }
        .tabViewStyle(.verticalPage)
    }
}
