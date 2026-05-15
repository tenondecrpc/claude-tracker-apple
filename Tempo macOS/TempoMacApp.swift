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

        // When `SessionEventWriter` detects that a Claude Code session
        // just completed, trigger an immediate usage poll. This is the
        // missing event-driven trigger that makes the popover AND macOS
        // widget refresh on activity, instead of waiting for the next
        // 15-minute scheduled poll. The accountId is forwarded so the
        // poller can target the correct worker; we fall back to the
        // active account when the session is tagged as `unassigned`
        // (CLI-only sessions that did not match any registered account).
        sessionEventWriter.onSessionWritten = { [weak self] accountId in
            guard let self else { return }
            let target = accountId == AccountIdentifier.unassignedAccountId
                ? self.registry.activeAccountId
                : accountId
            DevLog.trace(
                "AuthTrace",
                "Session-driven poll trigger sessionAccountId=\(accountId) targetAccountId=\(target ?? "nil")"
            )
            self.poller.pollNow(accountId: target)
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
        } catch {
            DiagnosticsCenter.shared.warning(
                kind: "icloud.alert-preferences.write",
                message: "Couldn't sync alert preferences to iCloud",
                error: error
            )
        }
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
        // Determine whether the visually-meaningful fields changed since
        // the last snapshot for this account. Only call
        // `reloadTimelines` when they did - WidgetKit has a daily reload
        // budget per extension and silently drops requests once it is
        // exhausted, so paying a reload for a snapshot that renders
        // identically wastes budget that a real change later in the day
        // will need. The freshness footer ("3 min ago") still advances
        // because the widget's own timeline policy schedules periodic
        // re-renders; we only skip the explicit reload signal.
        let previousSnapshot = TempoWidgetSnapshotStore.read(
            accountId: usage.accountId,
            platform: .macOS
        )
        let diff = previousSnapshot.flatMap { firstVisualDifference(previous: $0, next: snapshot) }
        let visuallyChanged = previousSnapshot == nil || diff != nil
        if let diff {
            DevLog.trace(
                "AuthTrace",
                "Widget snapshot visual diff platform=macOS accountId=\(usage.accountId) field=\(diff)"
            )
        }

        // Detect a real active-account pointer flip by reading the
        // pre-existing pointer before we (potentially) overwrite it.
        // Without this, every poll for the active account looks like a
        // "pointer flip" because the underlying store unconditionally
        // re-writes the same pointer file on each call. A real flip is
        // when the previous pointer value differs from the value we are
        // about to write.
        let previousActiveAccountId = TempoWidgetSnapshotStore.readActiveAccountId(platform: .macOS)
        let pointerWillFlip = registry.activeAccountId == usage.accountId
            && previousActiveAccountId != usage.accountId

        // Per-account snapshot goes to its own slot regardless of which
        // account is currently active, so background polls for a
        // non-active account keep that account's widget data fresh. The
        // active-account pointer is only updated when the freshly
        // written snapshot belongs to the registry's active account, so
        // polling a non-active account does not silently retarget the
        // default widgets.
        let wroteSnapshot = TempoWidgetSnapshotStore.write(snapshot, platform: .macOS)
        if registry.activeAccountId == usage.accountId {
            // Always re-write the pointer to maintain the invariant
            // (post-condition: pointer file exists and points to the
            // active account). The reload decision below uses
            // `pointerWillFlip` instead of the write's return value to
            // avoid treating idempotent re-writes as visual changes.
            _ = TempoWidgetSnapshotStore.write(
                activeAccountId: usage.accountId,
                platform: .macOS
            )
        }
        // Read-after-write check: confirm the host can read back exactly
        // what it just wrote. If this disagrees with `snapshot`, the App
        // Group container the host sees is not the one the extension
        // sees, or another writer is racing with this one. Cheap and
        // diagnostic-only; only runs when at least one write happened.
        if wroteSnapshot {
            if let readBack = TempoWidgetSnapshotStore.read(
                accountId: usage.accountId,
                platform: .macOS
            ) {
                // Tolerate sub-second drift on `updatedAt` because the
                // JSON encoder writes ISO8601 without fractional seconds,
                // so the read-back Date is always at second precision.
                let updatedAtDriftSeconds = abs(readBack.updatedAt.timeIntervalSince(snapshot.updatedAt))
                let drift = updatedAtDriftSeconds > 1.0
                    || readBack.utilization5h != snapshot.utilization5h
                    || readBack.utilization7d != snapshot.utilization7d
                DevLog.trace(
                    "AuthTrace",
                    "Widget snapshot read-after-write platform=macOS accountId=\(usage.accountId) drift=\(drift) wroteUpdatedAt=\(snapshot.updatedAt) readUpdatedAt=\(readBack.updatedAt) wroteUtil5h=\(snapshot.utilization5h) readUtil5h=\(readBack.utilization5h)"
                )
                if drift {
                    DiagnosticsCenter.shared.critical(
                        kind: "widget.snapshot.drift",
                        message: "Widget data and saved data don't match. Widget may show stale info."
                    )
                }
            } else {
                DevLog.trace(
                    "AuthTrace",
                    "Widget snapshot read-after-write FAILED platform=macOS accountId=\(usage.accountId) reason=read-returned-nil"
                )
                DiagnosticsCenter.shared.critical(
                    kind: "widget.snapshot.readafterwrite",
                    message: "Widget storage is not readable. Widget may not update."
                )
            }
        } else {
            // Write itself failed. The store already logged the
            // specific reason via its own DevLog. Surface as critical
            // because widgets won't update without the snapshot file.
            DiagnosticsCenter.shared.critical(
                kind: "widget.snapshot.write",
                message: "Couldn't save widget snapshot. Widget may not update."
            )
        }
        // Reload only when:
        //   - the active-account pointer actually flipped to a new
        //     accountId (widget needs to render a different account), OR
        //   - the visual fields of THIS account's snapshot changed.
        // Idempotent pointer re-writes do NOT count as a flip because
        // they would render identically; treating them as a reload
        // signal would burn the daily WidgetKit budget on every poll.
        let shouldReload = pointerWillFlip || (wroteSnapshot && visuallyChanged)
        if shouldReload {
            DevLog.trace(
                "AuthTrace",
                "Widget reload triggered platform=macOS accountId=\(usage.accountId) reason=\(pointerWillFlip ? "pointer-flip" : "visual-change")"
            )
            TempoWidgetSnapshotStore.reloadTimelines(for: .macOS)
        } else {
            DevLog.trace(
                "AuthTrace",
                "Widget reload skipped platform=macOS accountId=\(usage.accountId) reason=no-visual-change wroteSnapshot=\(wroteSnapshot) pointerWillFlip=\(pointerWillFlip) previousActive=\(previousActiveAccountId ?? "nil")"
            )
        }
    }

    /// Returns the name of the first visually-meaningful field where
    /// `previous` and `next` disagree, or `nil` when the two snapshots
    /// would render identically. Used to decide whether to call
    /// `WidgetCenter.reloadTimelines`: identical snapshots return `nil`
    /// and skip the reload to preserve the daily WidgetKit budget.
    ///
    /// The `updatedAt` freshness label is intentionally NOT compared
    /// because it advances on every successful poll without changing
    /// what the user sees in the main widget body. The widget's own
    /// timeline policy schedules periodic re-renders that pick up the
    /// new `updatedAt` without an explicit reload.
    ///
    /// Date fields (`resetAt5h`, `resetAt7d`) use a 1-second tolerance
    /// because `JSONEncoder` with `.iso8601` writes timestamps WITHOUT
    /// fractional seconds, while the server response is parsed WITH
    /// fractional seconds. Every successful poll therefore re-introduces
    /// sub-second precision that disappears the moment we encode the
    /// snapshot, so a strict `==` between the in-memory new snapshot
    /// and the previously-written-and-read-back snapshot would always
    /// disagree even when the server-provided timestamps are identical.
    private func firstVisualDifference(
        previous: WidgetUsageSnapshot,
        next: WidgetUsageSnapshot
    ) -> String? {
        if previous.accountId != next.accountId { return "accountId" }
        if previous.accountLabel != next.accountLabel { return "accountLabel" }
        if previous.utilization5h != next.utilization5h { return "utilization5h" }
        if previous.utilization7d != next.utilization7d { return "utilization7d" }
        if abs(previous.resetAt5h.timeIntervalSince(next.resetAt5h)) >= 1.0 { return "resetAt5h" }
        if abs(previous.resetAt7d.timeIntervalSince(next.resetAt7d)) >= 1.0 { return "resetAt7d" }
        if previous.isMocked != next.isMocked { return "isMocked" }
        if previous.isDoubleLimitPromoActive != next.isDoubleLimitPromoActive { return "isDoubleLimitPromoActive" }
        if previous.extraUsageEnabled != next.extraUsageEnabled { return "extraUsageEnabled" }
        if previous.extraUsageUsedAmountUSD != next.extraUsageUsedAmountUSD { return "extraUsageUsedAmountUSD" }
        if previous.extraUsageLimitAmountUSD != next.extraUsageLimitAmountUSD { return "extraUsageLimitAmountUSD" }
        if previous.extraUsageUtilizationPercent != next.extraUsageUtilizationPercent { return "extraUsageUtilizationPercent" }
        if previous.appearanceModeRawValue != next.appearanceModeRawValue { return "appearanceModeRawValue" }
        return nil
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
        if let polledAt = usage.polledAt {
            DevLog.trace(
                "AuthTrace",
                "Widget updatedAt resolved branch=polledAt accountId=\(usage.accountId) value=\(polledAt)"
            )
            return polledAt
        }
        if let existing = TempoWidgetSnapshotStore.read(
            accountId: usage.accountId,
            platform: .macOS
        ) {
            DevLog.trace(
                "AuthTrace",
                "Widget updatedAt resolved branch=existingSnapshot accountId=\(usage.accountId) value=\(existing.updatedAt)"
            )
            return existing.updatedAt
        }
        let fallback = usage.resetAt5h.addingTimeInterval(-5 * 3600)
        DevLog.trace(
            "AuthTrace",
            "Widget updatedAt resolved branch=fallback accountId=\(usage.accountId) value=\(fallback) resetAt5h=\(usage.resetAt5h)"
        )
        return fallback
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
        } catch {
            DiagnosticsCenter.shared.warning(
                kind: "icloud.appearance.write",
                message: "Couldn't sync appearance mode to iCloud",
                error: error
            )
        }
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

    /// Process-wide diagnostics sink. Held as `@State` so SwiftUI keeps
    /// the same `@Observable` reference across rebuilds and the banner
    /// reactively updates whenever `lastCritical` changes.
    @State private var diagnostics = DiagnosticsCenter.shared

    var body: some Scene {
        MenuBarExtra {
            MacMenuView(coordinator: coordinator)
                .frame(width: 320)
                .applyClaudeAppearance(coordinator.settings.appearanceMode)
                .syncWindowAppearance(coordinator.settings.appearanceMode)
                .environment(diagnostics)
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
                .environment(diagnostics)
        }
        .windowResizability(.contentSize)

        Window("Tempo for Claude", id: "stats-detail") {
            DetailWindowView(coordinator: coordinator, history: coordinator.history, localDB: coordinator.localDB)
                .applyClaudeAppearance(coordinator.settings.appearanceMode)
                .syncWindowAppearance(coordinator.settings.appearanceMode)
                .environment(diagnostics)
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
                .environment(diagnostics)
        }
        .windowResizability(.contentSize)
    }
}
