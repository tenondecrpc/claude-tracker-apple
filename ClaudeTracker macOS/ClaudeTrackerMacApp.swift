import SwiftUI

// MARK: - MacAppCoordinator

@Observable
@MainActor
final class MacAppCoordinator {
    let authState: MacAuthState
    let client: MacOSAPIClient
    let poller: UsagePoller

    init() {
        let authState = MacAuthState()
        let client = MacOSAPIClient(authState: authState)
        let poller = UsagePoller(client: client)

        self.authState = authState
        self.client = client
        self.poller = poller

        client.onSignOut = { [weak poller] in poller?.stop() }
    }

    func onLaunch() async {
        let restored = await client.tryRestoreSession()
        if restored {
            poller.start()
        }
    }

    func onAuthenticated() {
        poller.start()
    }
}

// MARK: - ClaudeTrackerMacApp

@main
struct ClaudeTrackerMacApp: App {
    @State private var coordinator = MacAppCoordinator()

    var body: some Scene {
        MenuBarExtra("ClaudeTracker", systemImage: "sparkles") {
            MacMenuView(coordinator: coordinator)
                .frame(width: 280)
                .task {
                    await coordinator.onLaunch()
                }
        }
        .menuBarExtraStyle(.window)
    }
}
