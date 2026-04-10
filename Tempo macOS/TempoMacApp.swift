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
    let sessionEventWriter: SessionEventWriter
    let appUpdater: AppUpdater
    let distribution: AppDistribution
    private var hasLaunched = false

    var supportsInAppUpdates: Bool {
        distribution.supportsInAppUpdates
    }

    init() {
        let authState = MacAuthState()
        let client = MacOSAPIClient(authState: authState)
        let poller = UsagePoller(client: client)
        let settings = MacSettingsStore()
        let launchAtLoginManager = LaunchAtLoginManager()
        let serviceStatusMonitor = ServiceStatusMonitor()
        let history = UsageHistory(syncHistoryViaICloud: settings.syncHistoryViaICloud)
        let localDB = ClaudeLocalDBReader()
        let sessionEventWriter = SessionEventWriter()
        let distribution = AppDistribution.current
        let appUpdater = AppUpdater(
            updatesEnabled: distribution.supportsInAppUpdates,
            autoCheckEnabled: { settings.autoCheckForUpdates && distribution.supportsInAppUpdates }
        )

        self.authState = authState
        self.client = client
        self.poller = poller
        self.settings = settings
        self.launchAtLoginManager = launchAtLoginManager
        self.serviceStatusMonitor = serviceStatusMonitor
        self.history = history
        self.localDB = localDB
        self.sessionEventWriter = sessionEventWriter
        self.appUpdater = appUpdater
        self.distribution = distribution

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

        sessionEventWriter.start()
        await appUpdater.checkOnLaunchIfNeeded()

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

// MARK: - TempoMacApp

@main
struct TempoMacApp: App {
    @State private var coordinator = MacAppCoordinator()

    var body: some Scene {
        MenuBarExtra {
            MacMenuView(coordinator: coordinator)
                .frame(width: 320)
                .preferredColorScheme(coordinator.settings.preferredColorScheme)
                .task {
                    await coordinator.onLaunch()
                }
        } label: {
            MenuBarIconView(
                usage: coordinator.poller.latestUsage,
                isAuthenticated: coordinator.authState.isAuthenticated,
                show5hPercentage: coordinator.settings.show5hPercentage,
                show5hResetTime: coordinator.settings.show5hResetTime,
                show7dPercentage: coordinator.settings.show7dPercentage,
                show7dResetTime: coordinator.settings.show7dResetTime,
                showExtraUsageCredits: coordinator.settings.showExtraUsageCredits,
                use24HourTime: coordinator.settings.use24HourTime
            )
        }
        .menuBarExtraStyle(.window)

        Window("Welcome", id: "welcome") {
            WelcomeWindowView(coordinator: coordinator)
                .frame(minWidth: 580, minHeight: 480)
                .preferredColorScheme(coordinator.settings.preferredColorScheme)
        }
        .windowResizability(.contentSize)

        Window("Tempo for Claude", id: "stats-detail") {
            DetailWindowView(coordinator: coordinator, history: coordinator.history, localDB: coordinator.localDB)
                .preferredColorScheme(coordinator.settings.preferredColorScheme)
        }
        .windowResizability(.contentSize)

        Settings {
            PreferencesWindowView(coordinator: coordinator)
                .preferredColorScheme(coordinator.settings.preferredColorScheme)
        }
        .windowResizability(.contentSize)
    }
}
