import SwiftUI

// MARK: - MacAppCoordinator

@Observable
@MainActor
final class MacAppCoordinator {
    let authState: MacAuthState
    let client: MacOSAPIClient
    let poller: UsagePoller
    let history: UsageHistory
    let localDB: ClaudeLocalDBReader
    private var hasLaunched = false

    init() {
        let authState = MacAuthState()
        let client = MacOSAPIClient(authState: authState)
        let poller = UsagePoller(client: client)
        let history = UsageHistory()
        let localDB = ClaudeLocalDBReader()

        self.authState = authState
        self.client = client
        self.poller = poller
        self.history = history
        self.localDB = localDB

        client.onSignOut = { [weak poller] in poller?.stop() }
        poller.onUsageState = { [weak history] state in
            history?.append(state)
        }
    }

    func onLaunch() async {
        guard !hasLaunched else { return }
        hasLaunched = true
        guard !authState.requiresExplicitSignIn else { return }
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
        MenuBarExtra {
            MacMenuView(coordinator: coordinator)
                .frame(width: 310)
                .task {
                    await coordinator.onLaunch()
                }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.medium")
                if let usage = coordinator.poller.latestUsage {
                    Text("\(Int(usage.utilization5h * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                }
            }
        }
        .menuBarExtraStyle(.window)

        Window("Welcome", id: "welcome") {
            WelcomeWindowView(coordinator: coordinator)
                .frame(minWidth: 580, minHeight: 480)
        }
        .windowResizability(.contentSize)

        Window("Stats", id: "stats-detail") {
            StatsDetailView(coordinator: coordinator, history: coordinator.history, localDB: coordinator.localDB)
        }
        .windowResizability(.contentSize)
    }
}
