import SwiftUI

struct DashboardTabView: View {
    let store: IOSAppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                titleSection

                if store.isWatchPaired && !store.isWatchAppInstalled {
                    watchInstallBanner
                }

                if let usage = store.usage {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        dashboardContent(usage: usage, now: context.date)
                    }
                } else {
                    waitingCard
                }
            }
            .padding(16)
        }
        .background(ClaudeCodeTheme.background)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Dashboard")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            Text("Live usage synced from your Mac via iCloud")
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func dashboardContent(usage: UsageState, now: Date) -> some View {
        let sessionColor = UtilizationSeverity(utilization: usage.utilization5h).usageColor(normal: ClaudeCodeTheme.Usage.session)
        let weeklyColor = UtilizationSeverity(utilization: usage.utilization7d).usageColor(normal: ClaudeCodeTheme.Usage.weekly)

        if case .stale(let since) = store.usageSyncStatus {
            statusCard(
                title: "Mac App Not Responding",
                subtitle: "Usage data is stale. Last update \(relativeAgeText(since)).",
                icon: "exclamationmark.triangle.fill",
                color: ClaudeCodeTheme.warning
            )
        }

        if let usageReadError = store.usageReadError {
            statusCard(
                title: "Usage Read Error",
                subtitle: usageReadError,
                icon: "xmark.octagon.fill",
                color: ClaudeCodeTheme.error
            )
        }

        card {
            VStack(alignment: .leading, spacing: 12) {
                if usage.isDoubleLimitPromoActive == true {
                    Label("2x promo active", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.warning)
                }

                UsageRingGauge(
                    sessionProgress: usage.utilization5h,
                    weeklyProgress: usage.utilization7d
                )
                .frame(height: 180)
                .frame(maxWidth: .infinity)

                HStack(spacing: 12) {
                    metricPill(
                        title: "5H",
                        value: percentLabel(usage.utilization5h),
                        subtitle: TimeFormatPolicy.sessionResetString(
                            resetAt: usage.resetAt5h,
                            now: now,
                            use24HourTime: store.use24HourTime
                        ),
                        color: sessionColor
                    )
                    metricPill(
                        title: "7D",
                        value: percentLabel(usage.utilization7d),
                        subtitle: TimeFormatPolicy.weeklyResetString(
                            resetAt: usage.resetAt7d,
                            use24HourTime: store.use24HourTime
                        ),
                        color: weeklyColor
                    )
                }
            }
        }

        card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Burn Rate")
                    .font(.headline)
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text("\(String(format: "%.1f", UsageHistoryTransformer.burnRate(utilization5h: usage.utilization5h, resetAt5h: usage.resetAt5h, now: now)))%/hr")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text(TimeFormatPolicy.sessionResetString(
                    resetAt: usage.resetAt5h,
                    now: now,
                    use24HourTime: store.use24HourTime
                ))
                .font(.footnote)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
        }

        if let extraUsage = usage.extraUsage, extraUsage.isEnabled {
            let extraColor = UtilizationSeverity(utilization: (extraUsage.utilization ?? 0) / 100.0).usageColor(normal: ClaudeCodeTheme.info)

            card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Extra Usage")
                        .font(.headline)
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)

                    if let used = extraUsage.usedCreditsAmount,
                       let limit = extraUsage.monthlyLimitAmount {
                        Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    }

                    ProgressView(value: (extraUsage.utilization ?? 0) / 100.0)
                        .tint(extraColor)
                        .background(ClaudeCodeTheme.progressTrack)
                }
            }
        }

        card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sync Status")
                    .font(.headline)
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                syncLine(
                    label: "Usage",
                    status: store.usageSyncStatus,
                    date: store.lastUsageUpdate
                )
                syncLine(
                    label: "History",
                    status: store.historySyncStatus,
                    date: store.lastHistoryUpdate
                )
            }
        }
    }

    private var watchInstallBanner: some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "applewatch.and.arrow.forward")
                    .foregroundStyle(ClaudeCodeTheme.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch App Available")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    Text("Open the Watch app on your iPhone and install Tempo, or enable Automatic App Install in Watch → General.")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                }
            }
        }
    }

    private var waitingCard: some View {
        card {
            VStack(spacing: 14) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(ClaudeCodeTheme.info)
                Text("Connect via Mac App")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text("Open Tempo on your Mac and sign in. This iPhone view updates from iCloud automatically.")
                    .font(.subheadline)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ClaudeCodeTheme.card)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(ClaudeCodeTheme.border.opacity(0.6), lineWidth: 1)
            )
    }

    private func metricPill(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudeCodeTheme.surface)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func percentLabel(_ utilization: Double) -> String {
        "\(Int(UsageHistoryTransformer.boundedPercent(utilization).rounded()))%"
    }

    private func relativeAgeText(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }

    private func statusCard(title: String, subtitle: String, icon: String, color: Color) -> some View {
        card {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                }
            }
        }
    }

    private func syncLine(label: String, status: iCloudUsageReader.SyncStatus, date: Date?) -> some View {
        let text: String
        let color: Color
        switch status {
        case .waiting:
            text = "Waiting for iCloud file"
            color = ClaudeCodeTheme.info
        case .syncing:
            if let date {
                text = "Updated \(date.formatted(date: .omitted, time: .shortened))"
            } else {
                text = "Syncing"
            }
            color = ClaudeCodeTheme.success
        case .stale(let since):
            text = "Stale since \(since.formatted(date: .omitted, time: .shortened))"
            color = ClaudeCodeTheme.warning
        }

        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text("\(label): \(text)")
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            Spacer()
        }
    }
}

private struct UsageRingGauge: View {
    let sessionProgress: Double
    let weeklyProgress: Double

    var body: some View {
        TempoUsageRing(
            sessionProgress: sessionProgress,
            weeklyProgress: weeklyProgress
        ) {
            VStack(spacing: 2) {
                Text("\(Int((sessionProgress * 100).rounded()))%")
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(UsageRingStyle.sessionColor(utilization: sessionProgress))
                Text("Session")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
        }
        .padding(.horizontal, 24)
    }
}
