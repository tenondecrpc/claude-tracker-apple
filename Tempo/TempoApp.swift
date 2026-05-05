import SwiftUI

// MARK: - AppCoordinator

/// Wires together iCloud read state, app UI store, and watch relay.
@MainActor
final class AppCoordinator {
    let iCloudReader: iCloudUsageReader
    let store: IOSAppStore
    let relay: WatchRelayManager
    let phoneAlertManager: PhoneAlertManager
    private var hasStartedPhoneAlerts = false
    private var hasBootstrapped = false

    init() {
        let iCloudReader = iCloudUsageReader()
        let store = IOSAppStore(iCloudReader: iCloudReader)
        let relay = WatchRelayManager()
        let phoneAlertManager = PhoneAlertManager()

        self.iCloudReader = iCloudReader
        self.store = store
        self.relay = relay
        self.phoneAlertManager = phoneAlertManager

        DevLog.trace(
            "AlertTrace",
            "TempoApp coordinator init initialIPhoneAlerts=\(store.iPhoneAlertsEnabled) initialWatchAlerts=\(store.watchAlertsEnabled)"
        )

        iCloudReader.onUsageState = { [weak relay, weak iCloudReader, weak store] (state: UsageState) in
            DevLog.trace(
                "AlertTrace",
                "TempoApp received usage state utilization5h=\(state.utilization5h) utilization7d=\(state.utilization7d) historyCount=\(iCloudReader?.historySnapshots.count ?? 0)"
            )
            let updatedAt = iCloudReader?.lastReceivedAt ?? Date()
            let appearanceMode = store?.appearanceMode ?? .dark
            let snapshot = WidgetUsageSnapshot(
                usage: state,
                updatedAt: updatedAt,
                appearanceMode: appearanceMode
            )
            if TempoWidgetSnapshotStore.write(snapshot, platform: .iOS) {
                TempoWidgetSnapshotStore.reloadTimelines(for: .iOS)
            }
            relay?.send(
                state,
                history: iCloudReader?.historySnapshots ?? [],
                alertPreferences: store?.sessionAlertPreferences ?? .default,
                appearanceMode: appearanceMode
            )
        }
        iCloudReader.onSessionInfo = { [weak relay, weak store, weak phoneAlertManager] (session: SessionInfo) in
            let preferences = store?.sessionAlertPreferences ?? .default
            let appearanceMode = store?.appearanceMode ?? .dark
            DevLog.trace(
                "AlertTrace",
                "TempoApp received synced session id=\(session.sessionId) iPhoneAlerts=\(preferences.iPhoneAlertsEnabled) watchAlerts=\(preferences.watchAlertsEnabled)"
            )
            phoneAlertManager?.notifySessionCompletion(
                for: session,
                enabledInPreferences: preferences.iPhoneAlertsEnabled
            )
            relay?.sendSession(session, alertPreferences: preferences, appearanceMode: appearanceMode)
        }
        iCloudReader.onAlertPreferences = { [weak store] preferences in
            DevLog.trace(
                "AlertTrace",
                "TempoApp received synced alert preferences iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
            )
            Task { @MainActor in
                store?.applySyncedAlertPreferences(preferences)
            }
        }
        iCloudReader.onAppearanceMode = { [weak self] appearanceMode in
            Task { @MainActor in
                self?.store.applySyncedAppearanceMode(appearanceMode)
                self?.refreshWidgetAppearance(appearanceMode)
                self?.relay.sendAppearanceMode(appearanceMode)
                if let state = self?.iCloudReader.latestUsage {
                    self?.relay.send(
                        state,
                        history: self?.iCloudReader.historySnapshots ?? [],
                        alertPreferences: self?.store.sessionAlertPreferences ?? .default,
                        appearanceMode: appearanceMode
                    )
                }
            }
        }
        relay.onWatchStateChange = { [weak store] isPaired, isInstalled in
            Task { @MainActor in
                store?.updateWatchState(isPaired: isPaired, isInstalled: isInstalled)
            }
        }
        store.onSessionAlertPreferencesChange = { [weak relay, weak iCloudReader, weak phoneAlertManager, weak store] preferences in
            DevLog.trace(
                "AlertTrace",
                "TempoApp local preference change iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
            )
            phoneAlertManager?.syncAuthorization(enabledInPreferences: preferences.iPhoneAlertsEnabled)
            if let state = iCloudReader?.latestUsage {
                relay?.send(
                    state,
                    history: iCloudReader?.historySnapshots ?? [],
                    alertPreferences: preferences,
                    appearanceMode: store?.appearanceMode ?? .dark
                )
            }
            do {
                try AlertPreferencesSync.write(preferences)
            } catch {}
        }
        DevLog.trace("AlertTrace", "TempoApp coordinator wired callbacks; waiting for bootstrap")
    }

    /// Called after the boot view has had a chance to render.
    /// Splits the heavy iCloud + WatchConnectivity setup off the synchronous
    /// init path so the empty/loading state always renders immediately.
    func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        relay.activate()
        DevLog.trace("AlertTrace", "TempoApp requested WatchRelay activation")
        iCloudReader.start()
        DevLog.trace("AlertTrace", "TempoApp started iCloudUsageReader from bootstrap")
    }

    // MARK: - Lifecycle

    func onBecomeActive() {
        DevLog.trace(
            "AlertTrace",
            "TempoApp became active iPhoneAlerts=\(store.iPhoneAlertsEnabled) watchAlerts=\(store.watchAlertsEnabled)"
        )
        if hasStartedPhoneAlerts {
            phoneAlertManager.syncAuthorization(enabledInPreferences: store.iPhoneAlertsEnabled)
        } else {
            hasStartedPhoneAlerts = true
            phoneAlertManager.syncAuthorization(enabledInPreferences: store.iPhoneAlertsEnabled)
        }
        iCloudReader.restart()
        store.refreshStaleness()
    }

    private func refreshWidgetAppearance(_ appearanceMode: AppearanceMode) {
        guard let snapshot = TempoWidgetSnapshotStore.read(platform: .iOS) else { return }
        let refreshedSnapshot = WidgetUsageSnapshot(snapshot: snapshot, appearanceMode: appearanceMode)
        if TempoWidgetSnapshotStore.write(refreshedSnapshot, platform: .iOS) {
            TempoWidgetSnapshotStore.reloadTimelines(for: .iOS)
        }
    }
}

// MARK: - TempoApp

@main
struct TempoApp: App {
    @State private var coordinator: AppCoordinator?
    @State private var hasRequestedCoordinatorStart = false
    @State private var widgetRoute: TempoWidgetRoute?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            rootView
                .onChange(of: scenePhase) { _, phase in
                    DevLog.trace("AlertTrace", "TempoApp scenePhase changed to \(String(describing: phase))")
                    if phase == .active {
                        coordinator?.onBecomeActive()
                    }
                }
                .onOpenURL { url in
                    widgetRoute = TempoWidgetRoute(url: url)
                }
        }
    }

    @ViewBuilder
    private var rootView: some View {
        if let coordinator {
            ContentView(store: coordinator.store, widgetRoute: widgetRoute)
                .applyClaudeAppearance(coordinator.store.appearanceMode)
        } else {
            BootView {
                Task { @MainActor in
                    await startCoordinatorAfterBootFrame()
                }
            }
                .applyClaudeAppearance(.dark)
        }
    }

    @MainActor
    private func startCoordinatorAfterBootFrame() async {
        guard !hasRequestedCoordinatorStart else { return }
        hasRequestedCoordinatorStart = true

        // Let BootView commit before AppCoordinator wires iCloud and WatchConnectivity.
        await Task.yield()

        DevLog.trace("AlertTrace", "TempoApp constructing AppCoordinator from BootView task")
        let newCoordinator = AppCoordinator()
        coordinator = newCoordinator
        DevLog.trace("AlertTrace", "TempoApp BootView task scenePhase=\(String(describing: scenePhase))")
        newCoordinator.bootstrap()
        if scenePhase == .active {
            newCoordinator.onBecomeActive()
        }
    }
}

private struct BootView: View {
    let onReadyToBootstrap: () -> Void

    var body: some View {
        ZStack {
            ClaudeCodeTheme.background
                .ignoresSafeArea()
            VStack(spacing: 16) {
                Image("LaunchLogo", label: Text("Tempo"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 84, height: 84)
                    .clipShape(.rect(cornerRadius: 18))
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(ClaudeCodeTheme.accent)
            }
        }
        .onAppear {
            DevLog.trace("AlertTrace", "TempoApp BootView appeared")
            onReadyToBootstrap()
        }
    }
}
