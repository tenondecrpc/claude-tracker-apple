import SwiftUI

// MARK: - AuthenticatedMenuView

struct AuthenticatedMenuView: View {
    let coordinator: MacAppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        // Read preference values outside TimelineView so observation invalidates immediately
        // when toggles change in the settings window.
        let use24HourTime = coordinator.settings.use24HourTime
        let showServiceStatus = coordinator.settings.serviceStatusMonitoring

        VStack(spacing: 0) {
            MenuBarHeaderView(
                onRefresh: { coordinator.poller.pollNow() },
                isPolling: coordinator.poller.isPolling
            )

            if let usage = coordinator.poller.latestUsage {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        usageContent(
                            usage: usage,
                            now: context.date,
                            use24HourTime: use24HourTime,
                            showServiceStatus: showServiceStatus
                        )
                        Divider().overlay(ClaudeTheme.progressTrack)
                        actionItems
                    }
                }
            } else if let errorMessage = coordinator.poller.lastPollError {
                errorView(message: errorMessage)
            } else {
                pollingView
            }
        }
        .background(ClaudeTheme.background)
        .preferredColorScheme(.dark)
    }

    // MARK: - Usage Content

    @ViewBuilder
    private func usageContent(
        usage: UsageState,
        now: Date,
        use24HourTime: Bool,
        showServiceStatus: Bool
    ) -> some View {
        let shouldShowServiceStatus = showServiceStatus && coordinator.serviceStatusMonitor.state != .operational

        VStack(alignment: .leading, spacing: 10) {
            if usage.isDoubleLimitPromoActive == true || shouldShowServiceStatus {
                VStack(alignment: .trailing, spacing: 4) {
                    if usage.isDoubleLimitPromoActive == true {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                            Text("2x promo active")
                                .font(.caption)
                                .foregroundStyle(ClaudeTheme.textSecondary)
                        }
                    }

                    if shouldShowServiceStatus {
                        serviceStatusRow
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Current Session
            Text("Current Session")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)
            Text("\(Int(usage.utilization5h * 100))%")
                .font(.title2.bold())
                .foregroundStyle(ClaudeTheme.textPrimary)
            UsageProgressBar(progress: usage.utilization5h)
            Text(
                TimeFormatPolicy.sessionResetString(
                    resetAt: usage.resetAt5h,
                    now: now,
                    use24HourTime: use24HourTime
                )
            )
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)

            Spacer().frame(height: 4)

            // Weekly Limit
            Text("Weekly Limit")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)
            Text("\(Int(usage.utilization7d * 100))%")
                .font(.title2.bold())
                .foregroundStyle(ClaudeTheme.textPrimary)
            UsageProgressBar(progress: usage.utilization7d)
            Text(
                TimeFormatPolicy.weeklyResetString(
                    resetAt: usage.resetAt7d,
                    use24HourTime: use24HourTime
                )
            )
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)

            // Extra Usage (only when enabled)
            if let extra = usage.extraUsage, extra.isEnabled {
                Spacer().frame(height: 4)

                Text("Extra Usage")
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
                if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                    Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                        .font(.title2.bold())
                        .foregroundStyle(ClaudeTheme.textPrimary)
                    UsageProgressBar(progress: (extra.utilization ?? 0) / 100.0)
                }
                Text("Resets monthly")
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }

            Spacer().frame(height: 4)

            // Burn-rate status
            let rate = burnRate(usage: usage, now: now)
            let onTrack = rate < 20
            HStack(spacing: 4) {
                Image(systemName: onTrack ? "checkmark.circle" : "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(onTrack ? .green : .orange)
                Text("\(onTrack ? "On track" : "High burn") · \(String(format: "%.1f", rate))%/hr")
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }

            // Last polled
            if let lastPollAt = coordinator.poller.lastPollAt {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                    Text(lastPollAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Action Items

    private var actionItems: some View {
        VStack(spacing: 0) {
            // Usage History — opens stats detail window
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
                .foregroundStyle(ClaudeTheme.textPrimary)
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
                            .foregroundStyle(ClaudeTheme.textSecondary)
                    }
                    Spacer()
                }
                .foregroundStyle(ClaudeTheme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider().overlay(ClaudeTheme.progressTrack)

            // Quit
            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ClaudeTheme.accent)
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
                .tint(ClaudeTheme.textSecondary)
            Text("Fetching usage…")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: - Error State

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                coordinator.poller.pollNow()
            }
            .buttonStyle(.plain)
            .font(.caption.bold())
            .foregroundStyle(ClaudeTheme.accent)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }

    // MARK: - Helpers

    private var serviceStatusRow: some View {
        let status = coordinator.serviceStatusMonitor.state
        return HStack(spacing: 4) {
            Image(systemName: iconForServiceState(status))
                .font(.caption)
                .foregroundStyle(colorForServiceState(status))
            Text(serviceText(for: status))
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)
        }
    }

    private func burnRate(usage: UsageState, now: Date) -> Double {
        let hoursUntilReset = max(0, usage.resetAt5h.timeIntervalSince(now) / 3600)
        let hoursElapsed = max(0.1, 5.0 - hoursUntilReset)
        return usage.utilization5h * 100.0 / hoursElapsed
    }

    private func serviceText(for state: ServiceHealthState) -> String {
        switch state {
        case .operational: return "Service: Operational"
        case .degraded: return "Service: Degraded"
        case .majorOutage: return "Service: Major Outage"
        case .stale: return "Service: Stale"
        case .unavailable: return "Service: Unavailable"
        }
    }

    private func iconForServiceState(_ state: ServiceHealthState) -> String {
        switch state {
        case .operational: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .majorOutage: return "xmark.octagon.fill"
        case .stale: return "clock.badge.exclamationmark"
        case .unavailable: return "questionmark.circle"
        }
    }

    private func colorForServiceState(_ state: ServiceHealthState) -> Color {
        switch state {
        case .operational: return .green
        case .degraded: return .orange
        case .majorOutage: return .red
        case .stale: return .yellow
        case .unavailable: return .gray
        }
    }
}
