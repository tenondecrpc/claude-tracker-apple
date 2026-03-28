import SwiftUI

// MARK: - AppCoordinator

/// Wires together the iCloud reader, WatchConnectivity relay, and legacy auth components.
@MainActor
final class AppCoordinator {
    let iCloudReader: iCloudUsageReader
    let relay: WatchRelayManager

    // Legacy iOS auth — retained but not primary path (macOS handles auth now)
    let authState: AuthState
    let client: AnthropicAPIClient

    init() {
        let iCloudReader = iCloudUsageReader()
        let relay = WatchRelayManager()
        let authState = AuthState()
        let client = AnthropicAPIClient(authState: authState)

        self.iCloudReader = iCloudReader
        self.relay = relay
        self.authState = authState
        self.client = client

        iCloudReader.onUsageState = { [weak relay] state in relay?.send(state) }
    }

    // MARK: - Lifecycle

    func onBecomeActive() {
        relay.activate()
        // Restart the metadata query to pick up iCloud changes from background (Task 5.3)
        iCloudReader.restart()
    }
}

// MARK: - ClaudeTrackerApp

@main
struct ClaudeTrackerApp: App {
    @State private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(iCloudReader: coordinator.iCloudReader)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        coordinator.onBecomeActive()
                    }
                }
        }
    }
}
