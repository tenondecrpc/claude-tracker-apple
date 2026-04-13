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
    }

    // MARK: - Usage Content

    @ViewBuilder
    private func usageContent(
        usage: UsageState,
        now: Date,
        use24HourTime: Bool
    ) -> some View {
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
                centerLabel: "\(Int(usage.utilization5h * 100))%"
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

                MenuActionRow(
                    icon: "arrow.right.square",
                    label: "Logout",
                    subtitle: coordinator.authState.accountEmail
                ) {
                    coordinator.client.signOut()
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
}
