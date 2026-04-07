import SwiftUI

// MARK: - MacAppCoordinator

@Observable
@MainActor
final class MacAppCoordinator {
    let authState: MacAuthState
    let client: MacOSAPIClient
    let poller: UsagePoller
    let settings: MacSettingsStore
    let launchAtLoginManager: LaunchAtLoginManager
    let serviceStatusMonitor: ServiceStatusMonitor
    let history: UsageHistory
    let localDB: ClaudeLocalDBReader
    private var hasLaunched = false

    init() {
        let authState = MacAuthState()
        let client = MacOSAPIClient(authState: authState)
        let poller = UsagePoller(client: client)
        let settings = MacSettingsStore()
        let launchAtLoginManager = LaunchAtLoginManager()
        let serviceStatusMonitor = ServiceStatusMonitor()
        let history = UsageHistory(syncHistoryViaICloud: settings.syncHistoryViaICloud)
        let localDB = ClaudeLocalDBReader()

        self.authState = authState
        self.client = client
        self.poller = poller
        self.settings = settings
        self.launchAtLoginManager = launchAtLoginManager
        self.serviceStatusMonitor = serviceStatusMonitor
        self.history = history
        self.localDB = localDB

        client.onSignOut = { [weak self] in
            self?.poller.stop()
            self?.serviceStatusMonitor.stop()
        }
        poller.onUsageState = { [weak history] state in
            history?.append(state)
        }

        settings.onServiceStatusMonitoringChanged = { [weak self] _ in
            self?.updateServiceStatusMonitoring()
        }
        settings.onSyncHistoryViaICloudChanged = { [weak history] enabled in
            history?.setSyncHistoryEnabled(enabled)
        }

        launchAtLoginManager.refresh()
        settings.updateLaunchAtLoginFromSystem(launchAtLoginManager.isEnabled)
        if settings.launchAtLogin != launchAtLoginManager.isEnabled {
            launchAtLoginManager.setEnabled(settings.launchAtLogin)
            settings.updateLaunchAtLoginFromSystem(launchAtLoginManager.isEnabled)
        }
    }

    func onLaunch() async {
        guard !hasLaunched else { return }
        hasLaunched = true
        guard !authState.requiresExplicitSignIn else { return }
        let restored = await client.tryRestoreSession()
        if restored {
            poller.start()
            updateServiceStatusMonitoring()
        }
    }

    func onAuthenticated() {
        poller.start()
        updateServiceStatusMonitoring()
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        launchAtLoginManager.setEnabled(enabled)
        settings.updateLaunchAtLoginFromSystem(launchAtLoginManager.isEnabled)
    }

    private func updateServiceStatusMonitoring() {
        let shouldRun = authState.isAuthenticated && settings.serviceStatusMonitoring
        if shouldRun {
            serviceStatusMonitor.start()
        } else {
            serviceStatusMonitor.stop()
        }
    }
}

// MARK: - ClaudeTrackerMacApp

@main
struct ClaudeTrackerMacApp: App {
    @State private var coordinator = MacAppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MacMenuView(coordinator: coordinator)
                .frame(width: 320)
                .task {
                    await coordinator.onLaunch()
                }
        } label: {
            MenuBarIconView(
                usage: coordinator.poller.latestUsage,
                isAuthenticated: coordinator.authState.isAuthenticated,
                showPercentage: coordinator.settings.showPercentageInMenuBar
            )
        }
        .menuBarExtraStyle(.window)

        Window("Welcome", id: "welcome") {
            WelcomeWindowView(coordinator: coordinator)
                .frame(minWidth: 580, minHeight: 480)
        }
        .windowResizability(.contentSize)

        Window("Tempo for Claude", id: "stats-detail") {
            DetailWindowView(coordinator: coordinator, history: coordinator.history, localDB: coordinator.localDB)
        }
        .windowResizability(.contentSize)
    }
}
