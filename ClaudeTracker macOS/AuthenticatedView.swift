import SwiftUI

// MARK: - AuthenticatedMenuView

struct AuthenticatedMenuView: View {
    let coordinator: MacAppCoordinator
    @Environment(\.openWindow) private var openWindow
    @State private var launchAtLogin = false

    var body: some View {
        VStack(spacing: 0) {
            MenuBarHeaderView(
                onRefresh: { coordinator.poller.pollNow() },
                isPolling: coordinator.poller.isPolling
            )

            if let usage = coordinator.poller.latestUsage {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        usageContent(usage: usage, now: context.date)
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
    private func usageContent(usage: UsageState, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Current Session
            Text("Current Session")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)
            Text("\(Int(usage.utilization5h * 100))%")
                .font(.title2.bold())
                .foregroundStyle(ClaudeTheme.textPrimary)
            UsageProgressBar(progress: usage.utilization5h)
            Text(resetCountdown(date: usage.resetAt5h, now: now))
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
            Text(weeklyReset(date: usage.resetAt7d))
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)

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
                openWindow(id: "stats-detail")
                NSApp.activate(ignoringOtherApps: true)
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

            // Launch at Login (placeholder toggle)
            HStack {
                Image(systemName: "power")
                Text("Launch at Login")
                Spacer()
                Toggle("", isOn: $launchAtLogin)
                    .labelsHidden()
                    .tint(ClaudeTheme.accent)
            }
            .foregroundStyle(ClaudeTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

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

    private func resetCountdown(date: Date, now: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSince(now) / 60))
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        return "Resets in \(minutes) min (\(timeFormatter.string(from: date)))"
    }

    private func weeklyReset(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, HH:mm"
        return "Resets \(formatter.string(from: date))"
    }

    private func burnRate(usage: UsageState, now: Date) -> Double {
        let hoursUntilReset = max(0, usage.resetAt5h.timeIntervalSince(now) / 3600)
        let hoursElapsed = max(0.1, 5.0 - hoursUntilReset)
        return usage.utilization5h * 100.0 / hoursElapsed
    }
}
