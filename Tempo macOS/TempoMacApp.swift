import SwiftUI

// MARK: - MacAppCoordinator

@Observable
@MainActor
final class MacAppCoordinator {
    // MARK: Multi-account stores (constructed first, in dependency order)
    //
    // `registry` is the single source of truth for known accounts and the
    // active selection on macOS. `accountMirror` projects the non-secret
    // fields to iCloud (`Tempo/accounts/<id>/account.json` and
    // `Tempo/accounts/index.json`) so iOS can discover them.
    // `accountRemovalService` composes `CredentialStore`, the mirror, and
    // the registry into a single "remove this account and everything tied
    // to it" entry point used by `MacOSAPIClient.signOut(for:)`.
    let registry: AccountRegistry
    let accountMirror: AccountRegistryICloudMirror
    let accountRemovalService: AccountRemovalService

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

    /// Synthetic accountId used to stand in for a signed-in account while
    /// demo mode is active. Registered in `registry` on enter and removed
    /// on exit so the active-account proxies in `UsagePoller` have
    /// somewhere to route demo usage.
    private static let demoAccountId = "demo@tempo.local"

    init() {
        // Multi-account scaffolding must be built before anything that
        // needs to key by `accountId`.
        let registry = AccountRegistry()
        let accountMirror = AccountRegistryICloudMirror()
        let accountRemovalService = AccountRemovalService(
            registry: registry,
            mirror: accountMirror
        )

        // One-shot sweep of the old single-slot Keychain credential and the
        // pre-Keychain JSON credential cache. Runs before polling / API
        // wiring so no restore path accidentally reads them.
        LegacyCredentialsCleanup.sweep()
        // Synthetic demo account must never persist across launches. Use
        // the full removal service so any leftover iCloud
        // `Tempo/accounts/demo@tempo.local/` directory and App Group
        // widget snapshot (from a prior run that crashed before
        // `exitDemoMode` could fire) are cleaned up too. Bare
        // `registry.remove` only purged the in-memory list and left the
        // iCloud directory, which iOS kept re-decoding on every
        // metadata refresh.
        accountRemovalService.removeAccount(accountId: Self.demoAccountId)

        let authState = MacAuthState()
        let client = MacOSAPIClient(
            authState: authState,
            registry: registry,
            removalService: accountRemovalService
        )
        let poller = UsagePoller(client: client, registry: registry)
        let settings = MacSettingsStore()
        let launchAtLoginManager = LaunchAtLoginManager()
        let serviceStatusMonitor = ServiceStatusMonitor()
        let history = UsageHistory()
        let localDB = ClaudeLocalDBReader(registry: registry)
        let sessionEventWriter = SessionEventWriter(registry: registry)
        let appUpdater = AppUpdater()

        self.registry = registry
        self.accountMirror = accountMirror
        self.accountRemovalService = accountRemovalService
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

        // Seed usage history buckets for any accounts that survived restart
        // so the detail window and charts have data to render before the
        // first poll completes.
        history.loadAll(accountIds: registry.accounts.map { $0.accountId })

        // Active-account reassignment invariant (task 4.5):
        //
        // By the time this callback fires, `MacOSAPIClient.signOut(for:)`
        // has already:
        //   1. Removed the per-account Keychain slot and iCloud
        //      `Tempo/accounts/<id>/` directory (via
        //      `AccountRemovalService.removeAccount(accountId:)`).
        //   2. Dropped the account from the registry. `AccountRegistry.remove`
        //      clears `activeAccountId` if the signed-out id was the active
        //      one; otherwise the active selection is untouched.
        //   3. Reassigned the active account when the active one was
        //      removed: `setActive(accountId: registry.accounts.first?.accountId)`,
        //      which promotes the first remaining account or clears the
        //      selection entirely when no accounts remain.
        //   4. Updated `authState` (isAuthenticated, requiresExplicitSignIn,
        //      authSource, accountEmail) so the UI reacts: the Welcome
        //      window opens when `requiresExplicitSignIn` flips true, and
        //      the popover/detail window rebind to the promoted account.
        //
        // This callback's job is to complete the teardown by reconciling
        // coordinator-owned state with the new registry shape.
        client.onSignOut = { [weak self] accountId in
            guard let self else { return }
            // Tear down the worker that belonged to the signed-out account
            // (and leave the other workers running). `syncWorkers()` diffs
            // against `registry.accounts` and stops any worker whose
            // account has been removed. Workers for any newly-promoted
            // active account are already running from the prior
            // `poller.start()` pass; we deliberately do not call
            // `poller.start()` here to avoid force-repolling healthy
            // workers.
            self.poller.syncWorkers()

            // Drop the stale in-memory history bucket for the signed-out
            // account. The iCloud `usage-history.json` file was already
            // removed by `AccountRemovalService`, so forgetting the
            // in-memory copy keeps `UsageHistory.histories` in lockstep
            // with the registry.
            self.history.forget(accountId: accountId)

            // Service status monitor is app-wide and only needs to stop
            // when NO account remains authenticated.
            if self.registry.accounts.isEmpty {
                self.serviceStatusMonitor.stop()
            }

            self.propagateActiveAccountSelection()
            self.isDemoMode = false
            DevLog.trace(
                "AuthTrace",
                "Coordinator handled sign-out accountId=\(accountId) remaining=\(self.registry.accounts.count) activeAccountId=\(self.registry.activeAccountId ?? "nil")"
            )
        }
        poller.onUsageState = { [weak self, weak history] state in
            history?.append(usage: state)
            self?.publishWidgetSnapshot(from: state)
        }

        settings.onServiceStatusMonitoringChanged = { [weak self] _ in
            self?.updateServiceStatusMonitoring()
        }
        // `MacSettingsStore.syncHistoryViaICloud` is intentionally left in
        // place for now so the Preferences UI keeps compiling, but it no
        // longer affects `UsageHistory`: the per-account store always
        // writes to its own iCloud path. Clean up the setting in a later
        // task alongside the Preferences pane rework (task 4.3).
        // TODO(multi-account task 4.3): drop `syncHistoryViaICloud`.
        settings.onSessionAlertPreferencesChanged = { [weak self] preferences in
            self?.syncAlertPreferencesToICloud(preferences)
        }
        settings.onAppearanceModeChanged = { [weak self] appearanceMode in
            self?.syncAppearanceModeToICloud(appearanceMode)
            self?.refreshPublishedWidgetAppearance()
        }

        launchAtLoginManager.refresh()
        if settings.launchAtLogin != launchAtLoginManager.isEnabled {
            launchAtLoginManager.setEnabled(settings.launchAtLogin)
        }
        settings.updateLaunchAtLoginFromSystem(launchAtLoginManager.isEnabled)

        // Seed the iCloud mirror once at startup so iOS discovery is
        // correct even if the user never mutates the registry in this
        // session. Gated on a non-empty registry per
        // so a CLI-only launch
        // does not thrash `Tempo/accounts/index.json` with a `count=0`
        // payload on every boot.
        if !registry.accounts.isEmpty {
            accountMirror.writeMirror(for: registry)
        }

        seedInitialWidgetSnapshotIfNeeded()
        syncAppearanceModeToICloud(settings.appearanceMode)
        // Sweep widget snapshots before the appearance refresh so we
        // don't waste a write on each orphan only to delete the
        // directory immediately afterwards.
        reconcileWidgetSnapshotsWithRegistry()
        refreshPublishedWidgetAppearance()
    }

    func onLaunch() async {
        guard !hasLaunched else { return }
        hasLaunched = true

        sessionEventWriter.start()
        seedInitialWidgetSnapshotIfNeeded()

        let isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasCompletedFirstLaunch")

        // Try to restore a Tempo OAuth session on every launch. Claude
        // Code CLI credentials are intentionally not read here because
        // that Keychain slot can require an explicit macOS authorization
        // prompt. The CLI path is only used from the Welcome window's
        // "Use existing Claude Code CLI session" action.
        let restored = await client.tryRestoreSession()

        if restored {
            // Mark the first launch complete so future launches behave
            // identically (no first-launch welcome side effect).
            if isFirstLaunch {
                UserDefaults.standard.set(true, forKey: "hasCompletedFirstLaunch")
            }
            // Refresh the iCloud mirror so index.json reflects any
            // registry mutation that happened during restore.
            if !registry.accounts.isEmpty {
                accountMirror.writeMirror(for: registry)
            }
            // Reload per-account history buckets so the detail window
            // has data before the first poll lands.
            history.loadAll(accountIds: registry.accounts.map { $0.accountId })
            poller.syncWorkers()
            propagateActiveAccountSelection()
            poller.start()
            updateServiceStatusMonitoring()
        }
        // If restore failed, do NOT open the Welcome window automatically. The
        // menu bar popover shows the "Not Signed In" view and the user
        // can click "Sign In" to open the Welcome window explicitly.
    }

    func onAuthenticated() {
        // `MacOSAPIClient.submitOAuthCode` has already added the account to
        // the registry and set it active. Re-sync the workers so the new
        // account gets its own polling worker, re-mirror to iCloud so iOS
        // discovers the account, and then kick off polling.
        poller.syncWorkers()
        poller.start()
        accountMirror.writeMirror(for: registry)
        history.loadAll(accountIds: registry.accounts.map { $0.accountId })
        propagateActiveAccountSelection()
        updateServiceStatusMonitoring()
    }

    func enterDemoMode() {
        isDemoMode = true
        authState.isAuthenticated = true

        // Register a synthetic demo account so the active-account proxy on
        // `UsagePoller` has a worker slot to route `latestUsage` through.
        // The worker stays idle because we never call `poller.start()` in
        // demo mode.
        let demo = Account(
            accountId: Self.demoAccountId,
            email: Self.demoAccountId,
            displayName: "Demo Account",
            createdAt: Date()
        )
        registry.add(demo)
        registry.setActive(accountId: Self.demoAccountId)
        poller.syncWorkers()

        poller.latestUsage = UsageState(
            accountId: Self.demoAccountId,
            utilization5h: 0.68,
            utilization7d: 0.42,
            resetAt5h: Date().addingTimeInterval(2 * 3600),
            resetAt7d: Date().addingTimeInterval(5 * 24 * 3600),
            isMocked: false,
            extraUsage: nil,
            isDoubleLimitPromoActive: nil
        )
        propagateActiveAccountSelection()
    }

    func exitDemoMode() {
        isDemoMode = false
        authState.isAuthenticated = false
        poller.latestUsage = nil
        // Use the full removal service so the demo account leaves no
        // trace in iCloud. `registry.remove(accountId:)` alone keeps the
        // App Group snapshot (handled later by reconcile) but does
        // nothing about the iCloud `Tempo/accounts/demo@tempo.local/`
        // directory, which would otherwise sync forever to iOS and
        // surface as log spam from `iCloudUsageReader.queryDidUpdate`
        // re-decoding the same orphaned `usage.json` /
        // `usage-history.json` on every metadata refresh. Keychain step
        // is a no-op for the demo account because no credentials were
        // ever stored under that id.
        accountRemovalService.removeAccount(accountId: Self.demoAccountId)
        poller.syncWorkers()
        propagateActiveAccountSelection()
        // Defensive sweep in case other orphans crept in. The
        // `removeAccount` call above already handled the demo's App
        // Group slot, so this is a no-op in the common case.
        reconcileWidgetSnapshotsWithRegistry()
    }

    func setActiveAccount(accountId: String?) {
        registry.setActive(accountId: accountId)
        poller.syncWorkers()
        propagateActiveAccountSelection()
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

    private func publishWidgetSnapshot(from usage: UsageState) {
        // The `updatedAt` timestamp on the widget snapshot is the
        // freshness signal driving the "just now" label and the timeline
        // refresh policy. It MUST only advance on successful polls, so
        // we always derive it from `usage.polledAt` (set by
        // `AccountPollingWorker.doPoll` only on success). When the
        // payload predates the `polledAt` field (legacy iCloud snapshot
        // written by an older build) we fall back to the existing
        // widget snapshot's `updatedAt` so we don't pretend old data was
        // just refreshed.
        let updatedAt = resolveUpdatedAt(for: usage)
        DevLog.trace(
            "AuthTrace",
            "Publishing macOS widget snapshot accountId=\(usage.accountId) activeAccountId=\(registry.activeAccountId ?? "nil") utilization5h=\(usage.utilization5h) utilization7d=\(usage.utilization7d) updatedAt=\(updatedAt)"
        )
        // Resolve the display label from the registry so the widget header
        // can identify which account the snapshot belongs to. Falls back
        // to the raw `accountId` when the account is not (yet) in the
        // registry (for example, during the brief window between an
        // OAuth exchange and the first `registry.add` call).
        let label = registry.accounts
            .first(where: { $0.accountId == usage.accountId })?
            .displayName ?? usage.accountId

        let snapshot = WidgetUsageSnapshot(
            usage: usage,
            updatedAt: updatedAt,
            accountLabel: label,
            appearanceMode: settings.appearanceMode
        )
        // Per-account snapshot goes to its own slot regardless of which
        // account is currently active, so background polls for a
        // non-active account keep that account's widget data fresh. The
        // active-account pointer is only updated when the freshly
        // written snapshot belongs to the registry's active account, so
        // polling a non-active account does not silently retarget the
        // default widgets.
        let wroteSnapshot = TempoWidgetSnapshotStore.write(snapshot, platform: .macOS)
        var wrotePointer = false
        if registry.activeAccountId == usage.accountId {
            wrotePointer = TempoWidgetSnapshotStore.write(
                activeAccountId: usage.accountId,
                platform: .macOS
            )
        }
        if wroteSnapshot || wrotePointer {
            TempoWidgetSnapshotStore.reloadTimelines(for: .macOS)
        }
    }

    /// Pick the `updatedAt` that should land on a freshly-written widget
    /// snapshot for `usage`.
    ///
    /// Precedence:
    /// 1. `usage.polledAt` when present (only set by a successful poll).
    /// 2. The existing on-disk widget snapshot's `updatedAt` for the
    ///    same accountId, so re-seeding from iCloud or propagating an
    ///    active-account change does NOT advance the freshness label.
    /// 3. `usage.resetAt5h - 5h` as a coarse lower bound when neither of
    ///    the above is available. This is conservative (i.e., older
    ///    than the next hourly refresh) so the widget still renders the
    ///    "stale" footer instead of pretending the data is fresh.
    private func resolveUpdatedAt(for usage: UsageState) -> Date {
        if let polledAt = usage.polledAt { return polledAt }
        if let existing = TempoWidgetSnapshotStore.read(
            accountId: usage.accountId,
            platform: .macOS
        ) {
            return existing.updatedAt
        }
        return usage.resetAt5h.addingTimeInterval(-5 * 3600)
    }

    private func propagateActiveAccountSelection() {
        guard let activeId = registry.activeAccountId else {
            DevLog.trace("AuthTrace", "Propagating widget active account cleared")
            if TempoWidgetSnapshotStore.write(activeAccountId: nil, platform: .macOS) {
                TempoWidgetSnapshotStore.reloadTimelines(for: .macOS)
            }
            return
        }

        if let usage = poller.worker(for: activeId)?.latestUsage {
            DevLog.trace(
                "AuthTrace",
                "Propagating widget active account from worker cache accountId=\(activeId)"
            )
            // The worker's `latestUsage` carries `polledAt` from its last
            // successful poll, so `publishWidgetSnapshot` will preserve
            // the real freshness timestamp instead of stamping `Date()`.
            publishWidgetSnapshot(from: usage)
            return
        }

        if let usage = readLatestUsageFromICloudMirror() {
            DevLog.trace(
                "AuthTrace",
                "Propagating widget active account from iCloud mirror accountId=\(activeId)"
            )
            // Pre-multi-account iCloud payloads may not have `polledAt`;
            // `publishWidgetSnapshot` falls back to the existing widget
            // snapshot's `updatedAt` (or a conservative bound) so the
            // freshness label does NOT jump to "just now" on relaunch.
            publishWidgetSnapshot(from: usage)
            return
        }

        DevLog.trace(
            "AuthTrace",
            "Propagating widget active account pointer only accountId=\(activeId)"
        )
        if TempoWidgetSnapshotStore.write(activeAccountId: activeId, platform: .macOS) {
            TempoWidgetSnapshotStore.reloadTimelines(for: .macOS)
        }
    }

    private func refreshPublishedWidgetAppearance() {
        // Only refresh snapshots for accounts that still exist in the
        // registry. Iterating `knownAccountIds(platform:)` would pick up
        // orphan directories left by previous builds or abandoned demo
        // sessions and re-stamp them with a current appearance, which
        // both wastes I/O and resurrects accounts that the user has
        // already removed. The startup reconcile + per-removal cleanup
        // keep the App Group tree pruned, so iterating the registry is
        // the safe source of truth.
        let accountIds = registry.accounts.map { $0.accountId }
        guard !accountIds.isEmpty else { return }

        var didWriteAny = false
        for accountId in accountIds {
            guard let existing = TempoWidgetSnapshotStore.read(
                accountId: accountId,
                platform: .macOS
            ) else { continue }
            let refreshed = WidgetUsageSnapshot(
                snapshot: existing,
                appearanceMode: settings.appearanceMode
            )
            if TempoWidgetSnapshotStore.write(refreshed, platform: .macOS) {
                didWriteAny = true
            }
        }
        if didWriteAny {
            TempoWidgetSnapshotStore.reloadTimelines(for: .macOS)
        }
    }

    /// Reconciles the App Group widget snapshot tree with the current
    /// registry: any per-account directory whose accountId is no longer
    /// present in `registry.accounts` is removed, and the active-account
    /// pointer is cleared when it references a removed account. Called
    /// once at startup to clean up orphans left by previous builds or
    /// abandoned demo sessions, and after every registry mutation
    /// (sign-out, demo enter/exit, active-account change) to keep the
    /// widget store in lockstep with the registry.
    private func reconcileWidgetSnapshotsWithRegistry() {
        let keep = Set(registry.accounts.map { $0.accountId })
        let removed = TempoWidgetSnapshotStore.reconcile(
            keepAccountIds: keep,
            platform: .macOS
        )
        if removed > 0 {
            DevLog.trace(
                "AuthTrace",
                "Widget snapshot reconcile removed \(removed) orphan(s); keep=\(keep.sorted())"
            )
            TempoWidgetSnapshotStore.reloadTimelines(for: .macOS)
        }
    }

    private func syncAppearanceModeToICloud(_ appearanceMode: AppearanceMode) {
        do {
            try AppearanceModeSync.write(appearanceMode)
        } catch {}
    }

    private func seedInitialWidgetSnapshotIfNeeded() {
        guard TempoWidgetSnapshotStore.read(platform: .macOS) == nil else { return }

        if let usage = readLatestUsageFromICloudMirror() {
            // Seeding from iCloud at app launch must NOT advance the
            // widget's freshness label: that label is only allowed to
            // advance on a successful poll. `publishWidgetSnapshot`
            // uses `usage.polledAt` when present, otherwise falls back
            // to the existing widget snapshot (none, since this is the
            // initial seed) or a conservative lower bound.
            publishWidgetSnapshot(from: usage)
            return
        }

        // No per-account iCloud snapshot is available. Without an
        // `accountId` we cannot fabricate a valid `UsageState` anymore
        // (the field is required), so leave the widget empty until the
        // first successful poll lands. This replaces the former
        // `history.snapshots.last` fallback, which is no longer available
        // on the per-account `UsageHistory`.
    }

    private func readLatestUsageFromICloudMirror() -> UsageState? {
        // Per-account iCloud layout: read the active account's
        // `usage.json` from `Tempo/accounts/<id>/`. If no account is
        // active yet (first launch before sign-in, or demo mode before
        // the registry is populated), there is nothing to seed.
        guard let activeId = registry.activeAccountId,
              let usageURL = TempoICloud.usageFileURL(for: activeId),
              let data = try? Data(contentsOf: usageURL)
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageState.self, from: data)
    }
}

// MARK: - TempoMacApp

@main
struct TempoMacApp: App {
    @State private var coordinator = MacAppCoordinator()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MacMenuView(coordinator: coordinator)
                .frame(width: 320)
                .applyClaudeAppearance(coordinator.settings.appearanceMode)
                .syncWindowAppearance(coordinator.settings.appearanceMode)
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
        .onChange(of: coordinator.authState.requiresExplicitSignIn) { _, needsSignIn in
            if needsSignIn {
                NSApp.keyWindow?.close()
                openWindow(id: "welcome")
                coordinator.authState.requiresExplicitSignIn = false
            }
        }

        Window("Welcome", id: "welcome") {
            WelcomeWindowView(coordinator: coordinator)
                .frame(minWidth: 580, idealHeight: 680)
                .applyClaudeAppearance(coordinator.settings.appearanceMode)
                .syncWindowAppearance(coordinator.settings.appearanceMode)
        }
        .windowResizability(.contentSize)

        Window("Tempo for Claude", id: "stats-detail") {
            DetailWindowView(coordinator: coordinator, history: coordinator.history, localDB: coordinator.localDB)
                .applyClaudeAppearance(coordinator.settings.appearanceMode)
                .syncWindowAppearance(coordinator.settings.appearanceMode)
                .onOpenURL { url in
                    // Widget taps (task 8.4) land here. When the URL
                    // carries an `accountId` query item we flip the
                    // registry's active account before the detail
                    // window's bindings react, so the window opens
                    // already showing the account the widget was
                    // rendering. Routes without an accountId keep the
                    // previous behaviour of opening the detail window
                    // on whichever account is already active.
                    guard let route = TempoWidgetRoute(url: url),
                          let accountId = route.accountId,
                          !accountId.isEmpty,
                          coordinator.registry.accounts.contains(where: { $0.accountId == accountId }),
                          coordinator.registry.activeAccountId != accountId
                    else { return }
                    coordinator.setActiveAccount(accountId: accountId)
                }
        }
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: Set([
            TempoWidgetRoute.Kind.dashboard.rawValue,
            TempoWidgetRoute.Kind.stats.rawValue,
        ]))

        Settings {
            PreferencesWindowView(coordinator: coordinator)
                .applyClaudeAppearance(coordinator.settings.appearanceMode)
                .syncWindowAppearance(coordinator.settings.appearanceMode)
        }
        .windowResizability(.contentSize)
    }
}
