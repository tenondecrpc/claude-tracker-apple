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
            let appearanceMode = store.appearanceMode
            // Per-account snapshot is written to its own slot, and the
            // pointer is updated so the default widgets render this
            // account (which is the active one by the earlier guard).
            // The helper coalesces redundant `reloadTimelines` calls so
            // pure no-op iCloud arrivals do not burn the WidgetKit
            // daily reload budget.
            self?.publishWidgetSnapshot(
                for: state,
                appearanceMode: appearanceMode,
                reason: "iCloudUsageState"
            )
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
            } catch {
                DiagnosticsCenter.shared.warning(
                    kind: "icloud.alert-preferences.write",
                    message: "Couldn't sync alert preferences to iCloud",
                    error: error
                )
            }
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

    /// Publishes a snapshot for the given active-account `state` to the
    /// shared App Group store and asks WidgetKit to reload only when the
    /// rendered output would actually change. Returns the snapshot that
    /// was published so callers that need to relay the same `UsageState`
    /// to the watch can read its `accountLabel` / `appearanceMode`.
    ///
    /// Reload coalescing rationale: WidgetKit applies a daily reload
    /// budget per extension and silently drops further reload requests
    /// once the budget is exhausted. Reloading on every iCloud arrival
    /// (active-account change, redundant `usage.json` write,
    /// no-op metadata fire) burns budget that real usage changes will
    /// need later in the day. We therefore reload only when the visual
    /// fields differ from the previously-stored snapshot for this same
    /// accountId, OR when the active-account pointer is genuinely
    /// flipping to a different accountId. Pure freshness label drift
    /// (`updatedAt`) is handled by the widget's own timeline policy.
    @discardableResult
    private func publishWidgetSnapshot(
        for state: UsageState,
        appearanceMode: AppearanceMode,
        reason: String
    ) -> WidgetUsageSnapshot {
        // Active-account flips and re-publishes from cached payloads
        // must NOT reset the freshness label. We use `state.polledAt`
        // when present (only set by macOS on a successful poll), then
        // the existing snapshot's `updatedAt` (round-trip through
        // iCloud might have stripped `polledAt`), and finally a
        // conservative lower bound that keeps the widget in its "stale"
        // footer rather than pretending the data is fresh.
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

        // Snapshot the previous values BEFORE writing so coalescing can
        // tell idempotent re-writes from real visual changes.
        let previousSnapshot = TempoWidgetSnapshotStore.read(
            accountId: state.accountId,
            platform: .iOS
        )
        let previousActiveAccountId = TempoWidgetSnapshotStore.readActiveAccountId(platform: .iOS)
        let diff = previousSnapshot.flatMap { firstVisualWidgetDifference(previous: $0, next: snapshot) }
        let visuallyChanged = previousSnapshot == nil || diff != nil
        let pointerWillFlip = previousActiveAccountId != state.accountId
        if let diff {
            DevLog.trace(
                "AlertTrace",
                "iOS widget visual diff accountId=\(state.accountId) field=\(diff) reason=\(reason)"
            )
        }

        let wroteSnapshot = TempoWidgetSnapshotStore.write(snapshot, platform: .iOS)
        // Always re-write the pointer to maintain the post-condition
        // (pointer file exists and points to the active account). The
        // reload decision below uses `pointerWillFlip` instead of the
        // write's return value to avoid treating idempotent re-writes
        // as visual changes.
        _ = TempoWidgetSnapshotStore.write(
            activeAccountId: state.accountId,
            platform: .iOS
        )

        let shouldReload = pointerWillFlip || (wroteSnapshot && visuallyChanged)
        if shouldReload {
            DevLog.trace(
                "AlertTrace",
                "iOS widget reload triggered accountId=\(state.accountId) reason=\(pointerWillFlip ? "pointer-flip" : "visual-change") trigger=\(reason)"
            )
            TempoWidgetSnapshotStore.reloadTimelines(for: .iOS)
        } else {
            DevLog.trace(
                "AlertTrace",
                "iOS widget reload skipped accountId=\(state.accountId) reason=no-visual-change wroteSnapshot=\(wroteSnapshot) pointerWillFlip=\(pointerWillFlip) previousActive=\(previousActiveAccountId ?? "nil") trigger=\(reason)"
            )
        }
        return snapshot
    }

    /// Returns the name of the first visually-meaningful field where
    /// `previous` and `next` disagree, or `nil` when the two snapshots
    /// would render identically. Mirror of the macOS coalescer in
    /// `Tempo macOS/TempoMacApp.swift`; the shared rationale lives there.
    /// Date fields use a 1-second tolerance because `JSONEncoder.iso8601`
    /// truncates fractional seconds while the server returns them, so
    /// every successful poll re-introduces sub-second precision that
    /// disappears on round-trip and would otherwise look like a change.
    private func firstVisualWidgetDifference(
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
            // active-account slot. The helper preserves `polledAt` (or
            // falls back to the existing snapshot's `updatedAt`) so
            // the freshness label does NOT advance, and coalesces the
            // reload to a real pointer flip.
            publishWidgetSnapshot(
                for: state,
                appearanceMode: appearanceMode,
                reason: "activeAccountChange"
            )
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

    /// Process-wide diagnostics sink. Held as `@State` so SwiftUI keeps
    /// the same `@Observable` reference across rebuilds and any view in
    /// the hierarchy can observe it via `@Environment(DiagnosticsCenter.self)`.
    @State private var diagnostics = DiagnosticsCenter.shared

    var body: some Scene {
        WindowGroup {
            rootView
                .environment(diagnostics)
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
