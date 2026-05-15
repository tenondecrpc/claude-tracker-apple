import SwiftUI

struct DashboardTabView: View {
    let store: IOSAppStore

    /// Drives presentation of the Accounts sheet opened from the header
    /// chip. Task 6.1 wires the chip tap and presents the sheet; task 6.2
    /// now renders the full account list, last-updated metadata, and
    /// "Set as active" actions via `AccountsSheetView`.
    @State private var showAccountsSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                accountChip

                titleSection

                if store.isWatchPaired && !store.isWatchAppInstalled {
                    watchInstallBanner
                }

                if store.isDemoMode {
                    demoBanner
                }

                if let usage = store.usage {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        dashboardContent(usage: usage, now: context.date)
                    }
                } else if store.isInitialSyncInProgress {
                    loadingCard
                } else {
                    waitingCard
                }
            }
            .padding(16)
        }
        .background(ClaudeCodeTheme.background)
        .sheet(isPresented: $showAccountsSheet) {
            AccountsSheetView(
                store: store,
                isPresented: $showAccountsSheet
            )
        }
    }

    /// Label shown inside the header chip.
    ///
    /// Task 6.1 uses the raw `accountId` (the canonicalized email) as the
    /// label because iOS does not yet materialize per-account
    /// `account.json` display names. Task 6.2 enriches this once the
    /// Accounts sheet loads per-account metadata.
    ///
    /// Returns "No account" when neither an explicitly chosen
    /// `activeAccountId` nor a discovered account is available. The chip
    /// stays tappable in that state so the sheet can explain how to add
    /// an account via the Mac app.
    private var accountChipLabel: String {
        if let id = store.resolvedAccountId, !id.isEmpty {
            return id
        }
        return "No account"
    }

    private var accountChip: some View {
        Button {
            showAccountsSheet = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Text(accountChipLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ClaudeCodeTheme.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(ClaudeCodeTheme.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(ClaudeCodeTheme.border.opacity(0.6), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Active account: \(accountChipLabel)")
        .accessibilityHint("Opens the accounts list")
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

        // Surface critical diagnostics ABOVE the existing usage-read /
        // staleness cards. Only renders when `lastCritical` is set; the
        // banner is dismissible by the user via its own button.
        DiagnosticsBannerView()

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
            let extraColor = UtilizationSeverity(utilization: (extraUsage.utilization ?? 0) / 100.0).usageColor(normal: ClaudeCodeTheme.Usage.normal)

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

    private var demoBanner: some View {
        card {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(ClaudeCodeTheme.warning)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Demo Mode")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    Text("Showing sample data. Connect a Mac to see your real usage.")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                }
                Spacer()
                Button("Exit") {
                    store.exitDemoMode()
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ClaudeCodeTheme.accent)
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

    private var loadingCard: some View {
        card {
            VStack(spacing: 14) {
                Image("LaunchLogo", label: Text("Tempo"))
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(.rect(cornerRadius: 16))
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(ClaudeCodeTheme.accent)
                Text("Syncing from iCloud…")
                    .font(.subheadline)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
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

                Button {
                    store.enterDemoMode()
                } label: {
                    Text("Try Demo")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(ClaudeCodeTheme.textSecondary.opacity(0.12))
                .clipShape(.rect(cornerRadius: 10))
                .padding(.top, 4)
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
                Text("5H")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
        }
        .padding(.horizontal, 24)
    }
}

/// Accounts sheet opened from the dashboard header chip (task 6.2).
///
/// Lists every account the iOS reader has discovered from
/// `Tempo/accounts/index.json` (falling back to any per-account
/// `usage.json` directories the reader found before the index landed).
/// Each row shows the canonical accountId as the label (iOS does not yet
/// materialize `account.json` display names), a relative "last updated"
/// time from `iCloudUsageReader.usageUpdatedAtByAccount`, and a checkmark
/// when the row matches the store's active account.
///
/// Tapping a row calls `IOSAppStore.setActiveAccount(accountId:)` and
/// dismisses the sheet. Adding an account remains a macOS-only flow, so
/// the sheet footer always points users at the Mac app instead of
/// offering an iOS Add action. When no accounts have been discovered
/// yet, the sheet shows an empty state with the same footer text.
private struct AccountsSheetView: View {
    let store: IOSAppStore
    @Binding var isPresented: Bool

    private let addAccountFooterText =
        "To add an account, open Tempo for Claude on your Mac and sign in."

    private let emptyStateText =
        "No accounts yet. Sign in on your Mac to get started."

    /// Account ids to render as real, switchable accounts. Excludes the
    /// `"unassigned"` bucket because CLI-only session data is not a
    /// switchable account on iOS.
    private var accountIds: [String] {
        let raw: [String]
        if !store.iCloudReader.knownAccountIds.isEmpty {
            raw = store.iCloudReader.knownAccountIds
        } else {
            raw = store.iCloudReader.usageByAccount.keys.sorted()
        }
        return raw.filter { $0 != AccountIdentifier.unassignedAccountId }
    }

    /// Resolves the accountId that should carry the active checkmark.
    /// Prefers the explicit `activeAccountId` selection; falls back to
    /// `resolvedAccountId` so the first-discovered default still shows as
    /// active before the user has tapped anything.
    private var activeAccountId: String? {
        store.activeAccountId ?? store.resolvedAccountId
    }

    var body: some View {
        NavigationStack {
            Group {
                if accountIds.isEmpty {
                    emptyState
                } else {
                    accountList
                }
            }
            .background(ClaudeCodeTheme.background)
            .navigationTitle("Accounts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundStyle(ClaudeCodeTheme.accent)
                }
            }
        }
    }

    private var accountList: some View {
        List {
            if !accountIds.isEmpty {
                Section {
                    ForEach(accountIds, id: \.self) { accountId in
                        accountRow(accountId: accountId)
                    }
                }
            }

            Section {
                Text(addAccountFooterText)
                    .font(.footnote)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ClaudeCodeTheme.background)
    }

    @ViewBuilder
    private func accountRow(accountId: String) -> some View {
        let isActive = accountId == activeAccountId
        Button {
            store.setActiveAccount(accountId: accountId)
            isPresented = false
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(accountId)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(lastUpdatedLabel(for: accountId))
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(ClaudeCodeTheme.accent)
                        .accessibilityLabel("Active account")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isActive ? "Already the active account" : "Sets this as the active account")
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            Text(emptyStateText)
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(addAccountFooterText)
                .font(.footnote)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    /// Builds the "Updated X ago" or "No data yet" label from the
    /// reader's per-account timestamp map.
    private func lastUpdatedLabel(for accountId: String) -> String {
        guard let date = store.iCloudReader.usageUpdatedAtByAccount[accountId] else {
            return "No data yet"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}
