import SwiftUI

// MARK: - DashboardPopoverView (ring dashboard for authenticated state)

struct DashboardPopoverView: View {
    let coordinator: MacAppCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        let use24HourTime = coordinator.settings.use24HourTime
        let showServiceStatus = coordinator.settings.serviceStatusMonitoring

        VStack(spacing: 0) {
            MenuBarHeaderView(
                onRefresh: { coordinator.poller.pollNow() },
                isPolling: coordinator.poller.isPolling,
                serviceState: showServiceStatus ? coordinator.serviceStatusMonitor.state : .operational,
                serviceName: showServiceStatus ? coordinator.serviceStatusMonitor.affectedServiceName : nil,
                trailingAccessory: { accountAccessory }
            )

            DiagnosticsBannerView()
                .padding(.horizontal, 17)
                .padding(.top, 8)

            if let feedback = coordinator.poller.refreshFeedback {
                RefreshFeedbackBannerView(feedback: feedback)
                    .padding(.horizontal, 17)
                    .padding(.top, 8)
            }

            if coordinator.isDemoMode {
                HStack(spacing: 6) {
                    Image(systemName: "eye.fill")
                        .font(.caption2)
                    Text("Demo Mode")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Button("Exit Demo") {
                        coordinator.exitDemoMode()
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ClaudeCodeTheme.accent)
                }
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(ClaudeCodeTheme.textSecondary.opacity(0.08))
            }

            contentState(use24HourTime: use24HourTime)

            actionItems
        }
        .background(ClaudeCodeTheme.background)
        .animation(.easeInOut(duration: 0.15), value: coordinator.poller.refreshFeedback?.id)
    }

    @ViewBuilder
    private func contentState(use24HourTime: Bool) -> some View {
        // Defense in depth: when the registry has no accounts, never render
        // the usage ring or the "Fetching usage..." spinner. The outer
        // `authState.isAuthenticated` gate in `SignInView` is the primary
        // correctness path after the CLI fallback fix; this registry
        // check catches any future regression of that invariant.
        if coordinator.registry.accounts.isEmpty {
            EmptyView()
        } else if let usage = coordinator.poller.latestUsage {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                usageContent(
                    usage: usage,
                    now: context.date,
                    use24HourTime: use24HourTime
                )
            }
        } else if let errorMessage = coordinator.poller.lastPollError {
            errorView(message: errorMessage)
        } else {
            pollingView
        }
    }

    // MARK: - Usage Content

    @ViewBuilder
    private func usageContent(
        usage: UsageState,
        now: Date,
        use24HourTime: Bool
    ) -> some View {
        let sessionColor = UtilizationSeverity(utilization: usage.utilization5h).usageColor(normal: ClaudeCodeTheme.Usage.session)
        let weeklyColor = UtilizationSeverity(utilization: usage.utilization7d).usageColor(normal: ClaudeCodeTheme.Usage.weekly)

        VStack(alignment: .leading, spacing: 13) {
            if usage.isDoubleLimitPromoActive == true {
                HStack(spacing: 6) {
                    Spacer()
                    Label("2x promo active", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.warning)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(ClaudeCodeTheme.warning.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            UsageRingView(
                sessionProgress: usage.utilization5h,
                weeklyProgress: usage.utilization7d,
                centerLabel: "\(Int(usage.utilization5h * 100))%",
                centerSubtitle: "5H"
            )
            .frame(width: 144, height: 144)
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                SessionPillChip(
                    value: "\(Int(usage.utilization5h * 100))%",
                    label: TimeFormatPolicy.sessionResetString(
                        resetAt: usage.resetAt5h,
                        now: now,
                        use24HourTime: use24HourTime
                    ),
                    accentColor: sessionColor
                )
                SessionPillChip(
                    value: "\(Int(usage.utilization7d * 100))%",
                    label: TimeFormatPolicy.weeklyResetString(
                        resetAt: usage.resetAt7d,
                        use24HourTime: use24HourTime
                    ),
                    accentColor: weeklyColor
                )
            }

            BurnRateCard(
                rate: burnRate(usage: usage, now: now),
                resetCountdown: TimeFormatPolicy.sessionResetString(
                    resetAt: usage.resetAt5h,
                    now: now,
                    use24HourTime: use24HourTime
                ),
                extraUsage: usage.extraUsage
            )

            if let lastPollAt = coordinator.poller.lastPollAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(ClaudeCodeTheme.textTertiary)
                    Text(lastPollAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(ClaudeCodeTheme.textTertiary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action Items

    private var actionItems: some View {
        VStack(spacing: 0) {
            Divider().overlay(ClaudeCodeTheme.progressTrack)

            VStack(spacing: 3) {
                MenuActionRow(icon: "chart.line.uptrend.xyaxis", label: "Stats") {
                    let menuWindow = NSApp.keyWindow
                    openWindow(id: "stats-detail")
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async { menuWindow?.close() }
                }

                MenuActionRow(icon: "gearshape", label: "Preferences") {
                    let menuWindow = NSApp.keyWindow
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.async { menuWindow?.close() }
                }

                // Defense in depth:
                // only render the Logout row when there is an account to
                // sign out of. Without this guard, a regression that
                // reintroduced `isAuthenticated == true` with an empty
                // registry would show a Logout control whose click does
                // nothing because `registry.activeAccountId` is nil.
                if !coordinator.registry.accounts.isEmpty {
                    MenuActionRow(
                        icon: "arrow.right.square",
                        label: "Logout",
                        subtitle: coordinator.authState.accountEmail
                    ) {
                        // TODO(multi-account task 4.1): surface a per-account
                        // sign-out affordance (menu of known accounts). For
                        // now, sign out the currently active account only.
                        if let activeId = coordinator.registry.activeAccountId {
                            coordinator.client.signOut(for: activeId)
                        }
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)

            Divider().overlay(ClaudeCodeTheme.progressTrack)

            VStack(spacing: 3) {
                MenuActionRow(icon: "power", label: "Quit Tempo", isDestructive: true) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
        }
    }

    // MARK: - Account accessory (header)

    /// Compact avatar Menu surfaced inside `MenuBarHeaderView`. Replaces
    /// the previous full-width "account row" so the prominent slot below
    /// the header is reserved for refresh feedback and alert banners. The
    /// active account's name and email live inside the menu (as a
    /// non-interactive section header) so users still have one click to
    /// see who is signed in without taking permanent vertical space.
    @ViewBuilder
    private var accountAccessory: some View {
        let accounts = coordinator.registry.accounts
        let activeId = coordinator.registry.activeAccountId
        let activeAccount = accounts.first(where: { $0.accountId == activeId })
        let hasAccounts = !accounts.isEmpty
        let helpLabel = accountAccessoryTooltip(for: activeAccount)

        Menu {
            if let activeAccount {
                // Section header surfaces the active account identity so
                // a single click reveals "who am I" without sacrificing
                // header real estate.
                Section {
                    Text(accountMenuLabel(for: activeAccount))
                    if !activeAccount.email.trimmingCharacters(in: .whitespaces).isEmpty,
                       activeAccount.email != accountMenuLabel(for: activeAccount) {
                        Text(activeAccount.email)
                    }
                }
                Divider()
            }

            if hasAccounts {
                Section {
                    ForEach(accounts) { account in
                        if account.accountId != activeId {
                            Button("Set as active: \(accountMenuLabel(for: account))") {
                                coordinator.setActiveAccount(accountId: account.accountId)
                            }
                        }
                    }
                }
                Divider()
            }

            Button("Switch account") {
                // Route through the existing onChange hook in
                // `TempoMacApp.swift`, which closes the current window and
                // opens the Welcome window when `requiresExplicitSignIn`
                // flips true.
                coordinator.authState.requiresExplicitSignIn = true
            }
        } label: {
            AccountAvatarLabel(
                initial: accountInitial(for: activeAccount),
                isSignedIn: hasAccounts
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(helpLabel)
    }

    private func accountInitial(for account: Account?) -> String {
        guard let account else { return "?" }
        let name = account.displayName.trimmingCharacters(in: .whitespaces)
        let email = account.email.trimmingCharacters(in: .whitespaces)
        let source = !name.isEmpty ? name : (!email.isEmpty ? email : account.accountId)
        return source.first.map { String($0).uppercased() } ?? "?"
    }

    private func accountAccessoryTooltip(for account: Account?) -> String {
        guard let account else { return "Not signed in" }
        let name = accountMenuLabel(for: account)
        let email = account.email.trimmingCharacters(in: .whitespaces)
        if !email.isEmpty && email != name {
            return "\(name) - \(email)"
        }
        return name
    }

    private func accountMenuLabel(for account: Account) -> String {
        let trimmedDisplay = account.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplay.isEmpty { return trimmedDisplay }
        let trimmedEmail = account.email.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedEmail.isEmpty { return trimmedEmail }
        return account.accountId
    }

    // MARK: - Loading Placeholder

    private var pollingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(ClaudeCodeTheme.textSecondary)
            Text("Fetching usage…")
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: - Error State

    private func errorView(message: String) -> some View {
        let isRateLimited = coordinator.poller.isRateLimited
        let retryLabel = coordinator.poller.rateLimitRetryLabel
        let signInSource = coordinator.authState.authSource == .cliSession ? "Claude Code" : "browser OAuth"

        return VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(ClaudeCodeTheme.warning)

            VStack(spacing: 5) {
                Text(isRateLimited ? "Usage temporarily unavailable" : "Unable to update usage")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    .multilineTextAlignment(.center)

                if isRateLimited {
                    Text("Signed in via \(signInSource). The usage API asked Tempo to retry in \(retryLabel ?? "a few minutes").")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            Button(isRateLimited ? "Retry in \(retryLabel ?? "a few minutes")" : "Retry") {
                coordinator.poller.pollNow()
            }
            .buttonStyle(.plain)
            .font(.caption.bold())
            .foregroundStyle(isRateLimited ? ClaudeCodeTheme.textTertiary : ClaudeCodeTheme.accent)
            .disabled(isRateLimited)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: - Helpers

    private func burnRate(usage: UsageState, now: Date) -> Double {
        let hoursUntilReset = max(0, usage.resetAt5h.timeIntervalSince(now) / 3600)
        let hoursElapsed = max(0.1, 5.0 - hoursUntilReset)
        return usage.utilization5h * 100.0 / hoursElapsed
    }
}

// MARK: - AccountAvatarLabel
//
// Compact label rendered inside the popover header's account Menu. Shows
// a single-letter monogram for the active account, falling back to a
// person glyph when no account is signed in. Click is handled by the
// surrounding `Menu`.

private struct AccountAvatarLabel: View {
    let initial: String
    let isSignedIn: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isSignedIn ? ClaudeCodeTheme.accentMuted : ClaudeCodeTheme.surface)
                .overlay(
                    Circle().stroke(
                        isSignedIn
                            ? ClaudeCodeTheme.accent.opacity(0.55)
                            : ClaudeCodeTheme.progressTrack,
                        lineWidth: 1
                    )
                )

            if isSignedIn {
                Text(initial)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ClaudeCodeTheme.accent)
            } else {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(ClaudeCodeTheme.textTertiary)
            }
        }
        .frame(width: 22, height: 22)
        .contentShape(Circle())
    }
}
