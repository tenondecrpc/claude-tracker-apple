import SwiftUI

// MARK: - DashboardPopoverView (ring dashboard for authenticated state)

struct DashboardPopoverView: View {
    let coordinator: MacAppCoordinator
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var isCheckingUpdates = false
    @State private var updateStatusMessage: String?
    @State private var updateVersion: String?

    var body: some View {
        let use24HourTime = coordinator.settings.use24HourTime
        let showServiceStatus = coordinator.settings.serviceStatusMonitoring

        VStack(spacing: 0) {
            MenuBarHeaderView(
                onRefresh: { coordinator.poller.pollNow() },
                isPolling: coordinator.poller.isPolling,
                serviceState: showServiceStatus ? coordinator.serviceStatusMonitor.state : .operational
            )

            if let usage = coordinator.poller.latestUsage {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        usageContent(
                            usage: usage,
                            now: context.date,
                            use24HourTime: use24HourTime
                        )
                        Divider().overlay(ClaudeCodeTheme.progressTrack)
                        actionItems
                    }
                }
            } else if let errorMessage = coordinator.poller.lastPollError {
                errorView(message: errorMessage)
            } else {
                pollingView
            }
        }
        .background(ClaudeCodeTheme.background)
        .onAppear {
            updateVersion = coordinator.appUpdater.availableVersion
            updateStatusMessage = coordinator.appUpdater.statusMessage
        }
    }

    // MARK: - Usage Content

    @ViewBuilder
    private func usageContent(
        usage: UsageState,
        now: Date,
        use24HourTime: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Promo indicator (above ring, right-aligned)
            if usage.isDoubleLimitPromoActive == true {
                HStack(spacing: 4) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.warning)
                    Text("2x promo active")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.warning)
                }
            }

            // Ring gauges (centered)
            UsageRingView(
                sessionProgress: usage.utilization5h,
                weeklyProgress: usage.utilization7d,
                centerLabel: "\(Int(usage.utilization5h * 100))%"
            )
            .frame(width: 150, height: 150)
            .frame(maxWidth: .infinity)

            // Pill chips
            HStack(spacing: 8) {
                SessionPillChip(
                    value: "\(Int(usage.utilization5h * 100))%",
                    label: TimeFormatPolicy.sessionResetString(
                        resetAt: usage.resetAt5h,
                        now: now,
                        use24HourTime: use24HourTime
                    ),
                    accentColor: ClaudeCodeTheme.accent
                )
                SessionPillChip(
                    value: "\(Int(usage.utilization7d * 100))%",
                    label: TimeFormatPolicy.weeklyResetString(
                        resetAt: usage.resetAt7d,
                        use24HourTime: use24HourTime
                    ),
                    accentColor: ClaudeCodeTheme.info
                )
            }

            // Burn rate card (with Extra Usage disclosure)
            BurnRateCard(
                rate: burnRate(usage: usage, now: now),
                resetCountdown: TimeFormatPolicy.sessionResetString(
                    resetAt: usage.resetAt5h,
                    now: now,
                    use24HourTime: use24HourTime
                ),
                extraUsage: usage.extraUsage
            )

            // Last polled
            if let lastPollAt = coordinator.poller.lastPollAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(ClaudeCodeTheme.textTertiary)
                    Text(lastPollAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(ClaudeCodeTheme.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action Items

    private var actionItems: some View {
        VStack(spacing: 0) {
            // Usage History
            Button {
                let menuWindow = NSApp.keyWindow
                openWindow(id: "stats-detail")
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.async {
                    menuWindow?.close()
                }
            } label: {
                HStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                    Text("Usage History")
                    Spacer()
                }
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().overlay(ClaudeCodeTheme.progressTrack)

            if coordinator.supportsInAppUpdates {
                // Updates
                Button {
                    if displayedUpdateVersion != nil {
                        coordinator.appUpdater.openLatestRelease()
                    } else {
                        Task {
                            await runManualUpdateCheck()
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: updateLeadingIconName)
                            .foregroundStyle(updateLeadingIconColor)
                        if let version = displayedUpdateVersion {
                            Text("Download Update \(version)")
                        } else {
                            Text("Check for Updates")
                        }
                        Spacer()
                    }
                    .foregroundStyle(displayedUpdateVersion != nil ? Color.green : ClaudeCodeTheme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isCheckingUpdates)

                Divider().overlay(ClaudeCodeTheme.progressTrack)
            }

            // Preferences
            Button {
                let menuWindow = NSApp.keyWindow
                openSettings()
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.async {
                    menuWindow?.close()
                }
            } label: {
                HStack {
                    Image(systemName: "gearshape")
                    Text("Preferences")
                    Spacer()
                }
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Logout
            Button {
                coordinator.client.signOut()
            } label: {
                HStack {
                    Image(systemName: "arrow.right.square")
                    Text("Logout")
                    if let email = coordinator.authState.accountEmail {
                        Text("(\(email))")
                            .font(.caption)
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    }
                    Spacer()
                }
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().overlay(ClaudeCodeTheme.progressTrack)

            // Quit
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ClaudeCodeTheme.error)
                .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
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
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(ClaudeCodeTheme.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                coordinator.poller.pollNow()
            }
            .buttonStyle(.plain)
            .font(.caption.bold())
            .foregroundStyle(ClaudeCodeTheme.accent)
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

    private var displayedUpdateVersion: String? {
        updateVersion ?? coordinator.appUpdater.availableVersion
    }

    private var updateLeadingIconName: String {
        if displayedUpdateVersion != nil {
            return "arrow.down.circle.fill"
        }
        if updateStatusMessage?.localizedCaseInsensitiveContains("failed") == true {
            return "exclamationmark.circle.fill"
        }
        return "arrow.down.circle"
    }

    private var updateLeadingIconColor: Color {
        if displayedUpdateVersion != nil {
            return .green
        }
        if updateStatusMessage?.localizedCaseInsensitiveContains("failed") == true {
            return ClaudeCodeTheme.warning
        }
        return ClaudeCodeTheme.textPrimary
    }

    private func runManualUpdateCheck() async {
        isCheckingUpdates = true
        updateStatusMessage = "Checking for updates..."
        await coordinator.appUpdater.checkForUpdates(userInitiated: true)
        updateVersion = coordinator.appUpdater.availableVersion
        updateStatusMessage = coordinator.appUpdater.statusMessage
        isCheckingUpdates = false
    }
}
