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

        iCloudReader.onUsageState = { [weak self, weak relay, weak store] (state: UsageState) in
            DevLog.trace(
                "AlertTrace",
                "TempoApp received usage state accountId=\(state.accountId) utilization5h=\(state.utilization5h) utilization7d=\(state.utilization7d) polledAt=\(state.polledAt.map(String.init(describing:)) ?? "nil")"
            )
            // Only the active account drives the watch relay and widget
            // snapshot, per design.md ("iOS relays only the active
            // account's UsageState"). Non-active accounts still populate
            // `iCloudReader.usageByAccount` so the dashboard account
            // picker can show their state when the user switches.
            guard let store, store.resolvedAccountId == state.accountId else {
                DevLog.trace(
                    "AlertTrace",
                    "TempoApp skipping relay/widget write for non-active account accountId=\(state.accountId) resolved=\(self?.store.resolvedAccountId ?? "nil")"
                )
                return
            }
            // The "last fetch" surface (widget freshness footer, watch
            // glance label) MUST only advance on a successful poll, so
            // we use the `polledAt` carried by the state. iOS reads
            // `usage.json` via NSMetadataQuery, which fires on iCloud
            // sync events that may be unrelated to a fresh fetch (for
            // example a no-op directory touch). Treating every iCloud
            // arrival as "just now" caused the iOS widget to flash a
            // fresh timestamp over stale data. Falling back to the
            // existing widget snapshot's `updatedAt` keeps legacy
            // payloads that lack `polledAt` from spuriously refreshing
            // the label.
            let updatedAt: Date = {
                if let polledAt = state.polledAt { return polledAt }
                if let existing = TempoWidgetSnapshotStore.read(
                    accountId: state.accountId,
                    platform: .iOS
                ) {
                    return existing.updatedAt
                }
                return state.resetAt5h.addingTimeInterval(-5 * 3600)
            }()
            let appearanceMode = store.appearanceMode
            let snapshot = WidgetUsageSnapshot(
                usage: state,
                updatedAt: updatedAt,
                accountLabel: state.accountId,
                appearanceMode: appearanceMode
            )
            // Per-account snapshot is written to its own slot, and the
            // pointer is updated so the default widgets render this
            // account (which is the active one by the earlier guard).
            // Both writes are gated together: if the snapshot write
            // fails we avoid pointing the widgets at a missing file.
            let wroteSnapshot = TempoWidgetSnapshotStore.write(snapshot, platform: .iOS)
            let wrotePointer = TempoWidgetSnapshotStore.write(
                activeAccountId: state.accountId,
                platform: .iOS
            )
            if wroteSnapshot || wrotePointer {
                TempoWidgetSnapshotStore.reloadTimelines(for: .iOS)
            }
            relay?.send(
                state,
                history: store.historySnapshots,
                alertPreferences: store.sessionAlertPreferences,
                appearanceMode: appearanceMode,
                accountLabel: state.accountId
            )
        }
        iCloudReader.onSessionInfo = { [weak relay, weak store, weak phoneAlertManager] (session: SessionInfo) in
            let preferences = store?.sessionAlertPreferences ?? .default
            let appearanceMode = store?.appearanceMode ?? .dark
            let activeAccountId = store?.resolvedAccountId
            DevLog.trace(
                "AlertTrace",
                "TempoApp received synced session id=\(session.sessionId) accountId=\(session.accountId) activeAccountId=\(activeAccountId ?? "nil") iPhoneAlerts=\(preferences.iPhoneAlertsEnabled) watchAlerts=\(preferences.watchAlertsEnabled)"
            )
            // Gate the local iPhone notification on the active account so
            // a completion from a non-active account doesn't fire a banner
            // that would surprise the user. The watch gate happens inside
            // `sendSession` (task 5.5) via the `activeAccountId` parameter.
            if let activeAccountId, session.accountId != activeAccountId {
                DevLog.trace(
                    "AlertTrace",
                    "TempoApp suppressing iPhone notification for session id=\(session.sessionId) accountId=\(session.accountId) because it does not match activeAccountId=\(activeAccountId)"
                )
            } else {
                phoneAlertManager?.notifySessionCompletion(
                    for: session,
                    enabledInPreferences: preferences.iPhoneAlertsEnabled
                )
            }
            relay?.sendSession(
                session,
                alertPreferences: preferences,
                appearanceMode: appearanceMode,
                activeAccountId: activeAccountId,
                accountLabel: session.accountId
            )
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
                if let state = self?.store.usage {
                    self?.relay.send(
                        state,
                        history: self?.store.historySnapshots ?? [],
                        alertPreferences: self?.store.sessionAlertPreferences ?? .default,
                        appearanceMode: appearanceMode,
                        accountLabel: state.accountId
                    )
                }
            }
        }
        relay.onWatchStateChange = { [weak store] isPaired, isInstalled in
            Task { @MainActor in
                store?.updateWatchState(isPaired: isPaired, isInstalled: isInstalled)
            }
        }
        relay.onFreshRelayRequested = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                DevLog.trace(
                    "AlertTrace",
                    "TempoApp handling RequestFreshRelay from watch"
                )
                self.iCloudReader.restart()
                // Re-send the active account's cached state immediately
                // so the watch gets data even if the iCloud file hasn't
                // changed (the restart will fire onUsageState again if
                // it has). If no active account or no cached usage, send
                // NoActiveAccount so the watch clears stale state.
                if let state = self.store.usage {
                    let appearanceMode = self.store.appearanceMode
                    self.relay.send(
                        state,
                        history: self.store.historySnapshots,
                        alertPreferences: self.store.sessionAlertPreferences,
                        appearanceMode: appearanceMode,
                        accountLabel: state.accountId
                    )
                    DevLog.trace(
                        "AlertTrace",
                        "TempoApp re-relayed usage for RequestFreshRelay accountId=\(state.accountId)"
                    )
                } else {
                    self.relay.sendNoActiveAccount()
                    DevLog.trace(
                        "AlertTrace",
                        "TempoApp sent NoActiveAccount for RequestFreshRelay (no cached usage)"
                    )
                }
            }
        }
        store.onSessionAlertPreferencesChange = { [weak relay, weak phoneAlertManager, weak store] preferences in
            DevLog.trace(
                "AlertTrace",
                "TempoApp local preference change iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
            )
            phoneAlertManager?.syncAuthorization(enabledInPreferences: preferences.iPhoneAlertsEnabled)
            if let state = store?.usage {
                relay?.send(
                    state,
                    history: store?.historySnapshots ?? [],
                    alertPreferences: preferences,
                    appearanceMode: store?.appearanceMode ?? .dark,
                    accountLabel: state.accountId
                )
            }
            do {
                try AlertPreferencesSync.write(preferences)
            } catch {}
        }
        // Reconcile the persisted iOS active account against the set of
        // accounts discovered from iCloud. When the user removes the
        // active account on macOS, the iCloud `accounts/index.json`
        // update tells iOS to move its selection (to the first remaining
        // account, or `nil` if there are none). This keeps iOS coherent
        // without requiring an explicit sign-out signal from macOS.
        iCloudReader.onAccountsIndexUpdated = { [weak self, weak store] accountIds in
            self?.reconcileWidgetSnapshotsWithIndex(accountIds: accountIds)
            guard let store else { return }
            if let currentId = store.activeAccountId,
               accountIds.contains(currentId) {
                // Persisted selection is still valid; nothing to do.
                DevLog.trace(
                    "AlertTrace",
                    "TempoApp accounts index update preserved activeAccountId=\(currentId) total=\(accountIds.count)"
                )
                return
            }
            let nextId = accountIds.first
            DevLog.trace(
                "AlertTrace",
                "TempoApp accounts index update reassigning activeAccountId from \(store.activeAccountId ?? "nil") to \(nextId ?? "nil") total=\(accountIds.count)"
            )
            store.setActiveAccount(accountId: nextId)
        }
        // User-initiated active-account changes (account chip, picker
        // sheet in task 6.x) land here. We re-send the active account's
        // usage state to the watch and republish its widget snapshot so
        // the glance and widgets flip in sync with the UI.
        store.onActiveAccountChange = { [weak self] accountId in
            guard let self else { return }
            DevLog.trace(
                "AlertTrace",
                "TempoApp active account changed accountId=\(accountId ?? "nil")"
            )
            self.propagateActiveAccountChange()
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
        // Refresh snapshots only for accounts that the iCloud reader has
        // discovered. Iterating `knownAccountIds(platform: .iOS)` would
        // pick up orphan App Group directories from removed accounts and
        // re-stamp their appearance, which both wastes writes and
        // resurrects accounts the user no longer owns. The
        // `onAccountsIndexUpdated` reconcile keeps the App Group tree
        // pruned, so iterating the iCloud index is the safe source of
        // truth here.
        let accountIds = iCloudReader.knownAccountIds
        guard !accountIds.isEmpty else { return }

        var didWriteAny = false
        for accountId in accountIds {
            guard let existing = TempoWidgetSnapshotStore.read(
                accountId: accountId,
                platform: .iOS
            ) else { continue }
            let refreshed = WidgetUsageSnapshot(
                snapshot: existing,
                appearanceMode: appearanceMode
            )
            if TempoWidgetSnapshotStore.write(refreshed, platform: .iOS) {
                didWriteAny = true
            }
        }
        if didWriteAny {
            TempoWidgetSnapshotStore.reloadTimelines(for: .iOS)
        }
    }

    /// Reconciles the iOS App Group widget snapshot tree against the
    /// authoritative `accounts/index.json` published by macOS. Called
    /// every time the iCloud reader emits a fresh accounts index, so
    /// sign-outs that happen on macOS clean up iOS widgets without an
    /// extra signal channel.
    ///
    /// Skipped when `accountIds` is empty so a transient empty index
    /// (for example, before the first ubiquity download lands) does not
    /// wipe still-valid snapshots. The first non-empty update is
    /// authoritative.
    private func reconcileWidgetSnapshotsWithIndex(accountIds: [String]) {
        guard !accountIds.isEmpty else { return }
        let keep = Set(accountIds)
        let removed = TempoWidgetSnapshotStore.reconcile(
            keepAccountIds: keep,
            platform: .iOS
        )
        if removed > 0 {
            DevLog.trace(
                "AlertTrace",
                "iOS widget snapshot reconcile removed \(removed) orphan(s); keep=\(accountIds)"
            )
            TempoWidgetSnapshotStore.reloadTimelines(for: .iOS)
        }
    }

    /// Publishes the current active account's usage to the watch relay
    /// and the iOS widget snapshot.
    ///
    /// This is the "iOS reacts to user-initiated active-account change"
    /// path (task 5.3). With task 5.4 in place, we either relay the
    /// active account's `UsageState` (carrying `accountId` / `accountLabel`)
    /// or send an explicit `NoActiveAccount` context so the watch clears
    /// its per-account state. Task 5.6 extends this to maintain the
    /// per-account widget snapshot tree: on every active-account change
    /// we refresh (or clear) the pointer in shared App Group storage so
    /// widgets flip alongside the watch.
    private func propagateActiveAccountChange() {
        let appearanceMode = store.appearanceMode
        if let state = store.usage {
            // Active-account flips are NOT a freshness event: we are
            // re-publishing a previously-fetched `UsageState` to a new
            // active-account slot. The widget's "last fetch" label MUST
            // only advance when a successful poll lands, so we keep the
            // payload's `polledAt` if present (it traveled with the
            // state from macOS poll -> iCloud -> iOS read), or fall
            // back to the existing snapshot's `updatedAt` for legacy
            // payloads. We never stamp `Date()` here.
            let updatedAt: Date = {
                if let polledAt = state.polledAt { return polledAt }
                if let existing = TempoWidgetSnapshotStore.read(
                    accountId: state.accountId,
                    platform: .iOS
                ) {
                    return existing.updatedAt
                }
                return state.resetAt5h.addingTimeInterval(-5 * 3600)
            }()
            let snapshot = WidgetUsageSnapshot(
                usage: state,
                updatedAt: updatedAt,
                accountLabel: state.accountId,
                appearanceMode: appearanceMode
            )
            // Write the snapshot to the per-account slot first so the
            // pointer never references a missing file, then flip the
            // pointer so the default widgets render this account.
            let wroteSnapshot = TempoWidgetSnapshotStore.write(snapshot, platform: .iOS)
            let wrotePointer = TempoWidgetSnapshotStore.write(
                activeAccountId: state.accountId,
                platform: .iOS
            )
            if wroteSnapshot || wrotePointer {
                TempoWidgetSnapshotStore.reloadTimelines(for: .iOS)
            }
            relay.send(
                state,
                history: store.historySnapshots,
                alertPreferences: store.sessionAlertPreferences,
                appearanceMode: appearanceMode,
                accountLabel: state.accountId
            )
        } else {
            // No usage available for the new active account (signed out,
            // no accounts discovered yet, or the active selection points
            // to an account whose iCloud payload hasn't arrived). Tell
            // the watch to clear its per-account surfaces and clear the
            // widget pointer so the default widgets render their "no
            // active account" placeholder instead of a stale account.
            DevLog.trace(
                "AlertTrace",
                "TempoApp propagateActiveAccountChange sending NoActiveAccount; resolvedAccountId=\(store.resolvedAccountId ?? "nil")"
            )
            // `resolvedAccountId` may still be non-nil here (falling back
            // to a discovered account) even when `store.usage` is nil,
            // so we prefer to point at whatever the store currently
            // resolves to; only clear the pointer when no account is
            // discoverable at all.
            if let fallbackId = store.resolvedAccountId, !fallbackId.isEmpty {
                if TempoWidgetSnapshotStore.write(activeAccountId: fallbackId, platform: .iOS) {
                    TempoWidgetSnapshotStore.reloadTimelines(for: .iOS)
                }
            } else {
                if TempoWidgetSnapshotStore.write(activeAccountId: nil, platform: .iOS) {
                    TempoWidgetSnapshotStore.reloadTimelines(for: .iOS)
                }
            }
            relay.sendNoActiveAccount()
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
                    guard let route = TempoWidgetRoute(url: url) else { return }
                    // Switching the active account is a user-initiated
                    // event (task 8.4): the widget they tapped was
                    // rendering a specific account, so the app should
                    // flip to that account before routing to the same
                    // tab. When the URL omits `accountId` the widget is
                    // just saying "open the app", so we leave the
                    // active-account selection alone.
                    if let accountId = route.accountId,
                       let coordinator,
                       coordinator.store.resolvedAccountId != accountId {
                        coordinator.store.setActiveAccount(accountId: accountId)
                    }
                    widgetRoute = route
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
