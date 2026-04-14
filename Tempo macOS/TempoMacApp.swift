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
    private var hasLaunched = false
    var isDemoMode = false

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
        let appUpdater = AppUpdater()

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

        client.onSignOut = { [weak self] in
            self?.poller.stop()
            self?.serviceStatusMonitor.stop()
            self?.isDemoMode = false
        }
        poller.onUsageState = { [weak self, weak history] state in
            history?.append(state)
            self?.publishWidgetSnapshot(from: state, updatedAt: Date())
        }

        settings.onServiceStatusMonitoringChanged = { [weak self] _ in
            self?.updateServiceStatusMonitoring()
        }
        settings.onSyncHistoryViaICloudChanged = { [weak history] enabled in
            history?.setSyncHistoryEnabled(enabled)
        }
        settings.onSessionAlertPreferencesChanged = { [weak self] preferences in
            self?.syncAlertPreferencesToICloud(preferences)
        }

        launchAtLoginManager.refresh()
        if settings.launchAtLogin != launchAtLoginManager.isEnabled {
            launchAtLoginManager.setEnabled(settings.launchAtLogin)
        }
        settings.updateLaunchAtLoginFromSystem(launchAtLoginManager.isEnabled)

        seedInitialWidgetSnapshotIfNeeded()
    }

    func onLaunch() async {
        guard !hasLaunched else { return }
        hasLaunched = true

        sessionEventWriter.start()
        seedInitialWidgetSnapshotIfNeeded()

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

    func enterDemoMode() {
        isDemoMode = true
        authState.isAuthenticated = true
        poller.latestUsage = UsageState(
            utilization5h: 0.68,
            utilization7d: 0.42,
            resetAt5h: Date().addingTimeInterval(2 * 3600),
            resetAt7d: Date().addingTimeInterval(5 * 24 * 3600),
            isMocked: false,
            extraUsage: nil,
            isDoubleLimitPromoActive: nil
        )
    }

    func exitDemoMode() {
        isDemoMode = false
        authState.isAuthenticated = false
        poller.latestUsage = nil
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

    private func syncAlertPreferencesToICloud(_ preferences: SessionAlertPreferences) {
        do {
            DevLog.trace(
                "AlertTrace",
                "MacAppCoordinator syncing alert preferences to iCloud iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
            )
            try AlertPreferencesSync.write(preferences)
        } catch {}
    }

    private func publishWidgetSnapshot(from usage: UsageState, updatedAt: Date) {
        let snapshot = WidgetUsageSnapshot(usage: usage, updatedAt: updatedAt)
        if TempoWidgetSnapshotStore.write(snapshot, platform: .macOS) {
            TempoWidgetSnapshotStore.reloadTimelines(for: .macOS)
        }
    }

    private func seedInitialWidgetSnapshotIfNeeded() {
        guard TempoWidgetSnapshotStore.read(platform: .macOS) == nil else { return }

        if let usage = readLatestUsageFromICloudMirror() {
            publishWidgetSnapshot(from: usage, updatedAt: Date())
            return
        }

        guard let last = history.snapshots.last else { return }
        let fallbackUsage = UsageState(
            utilization5h: last.utilization5h,
            utilization7d: last.utilization7d,
            resetAt5h: Date().addingTimeInterval(5 * 3600),
            resetAt7d: Date().addingTimeInterval(7 * 24 * 3600),
            isMocked: false,
            extraUsage: nil,
            isDoubleLimitPromoActive: nil
        )
        publishWidgetSnapshot(from: fallbackUsage, updatedAt: last.date)
    }

    private func readLatestUsageFromICloudMirror() -> UsageState? {
        let trackerDirectory: URL
        if let containerURL = FileManager.default.url(forUbiquityContainerIdentifier: TempoICloud.containerIdentifier) {
            trackerDirectory = containerURL.appendingPathComponent("Documents/Tempo", isDirectory: true)
        } else {
            trackerDirectory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Tempo", isDirectory: true)
        }

        let usageURL = trackerDirectory.appendingPathComponent("usage.json")
        guard let data = try? Data(contentsOf: usageURL) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageState.self, from: data)
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
            .task {
                await coordinator.onLaunch()
            }
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
        .handlesExternalEvents(matching: Set([
            TempoWidgetRoute.dashboard.rawValue,
            TempoWidgetRoute.stats.rawValue,
        ]))

        Settings {
            PreferencesWindowView(coordinator: coordinator)
                .preferredColorScheme(coordinator.settings.preferredColorScheme)
        }
        .windowResizability(.contentSize)
    }
}
