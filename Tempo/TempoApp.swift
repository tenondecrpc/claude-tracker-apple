import SwiftUI

// MARK: - AppCoordinator

/// Wires together iCloud read state, app UI store, and watch relay.
@MainActor
final class AppCoordinator {
    let iCloudReader: iCloudUsageReader
    let store: IOSAppStore
    let relay: WatchRelayManager

    init() {
        let iCloudReader = iCloudUsageReader()
        let store = IOSAppStore(iCloudReader: iCloudReader)
        let relay = WatchRelayManager()

        self.iCloudReader = iCloudReader
        self.store = store
        self.relay = relay

        iCloudReader.onUsageState = { [weak relay, weak iCloudReader] (state: UsageState) in
            relay?.send(state, history: iCloudReader?.historySnapshots ?? [])
        }
        iCloudReader.onSessionInfo = { [weak relay] (session: SessionInfo) in
            relay?.sendSession(session)
        }
        relay.onWatchStateChange = { [weak store] isPaired, isInstalled in
            Task { @MainActor in
                store?.updateWatchState(isPaired: isPaired, isInstalled: isInstalled)
            }
        }
        relay.activate()
        iCloudReader.start()
    }

    // MARK: - Lifecycle

    func onBecomeActive() {
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
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        coordinator.onBecomeActive()
                    }
                }
        }
    }
}
