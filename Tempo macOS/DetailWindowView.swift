import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

private struct SessionChartSegment: Identifiable {
    let snapshots: [UsageSnapshot]
    let isUsingExtraUsage: Bool

    var id: String {
        let first = snapshots.first?.date.timeIntervalSince1970 ?? 0
        let last = snapshots.last?.date.timeIntervalSince1970 ?? 0
        return "\(first)-\(last)-\(isUsingExtraUsage)"
    }
}

private struct ExtraUsageWindow: Identifiable {
    let start: Date
    let end: Date

    var id: String {
        "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)"
    }
}

// MARK: - DetailTab

enum DetailTab: String, CaseIterable {
    case overview    = "Overview"
    case activity    = "Activity"
    case preferences = "Preferences"
}

// MARK: - DetailWindowView

struct DetailWindowView: View {
    let coordinator: MacAppCoordinator
    let history: UsageHistory
    let localDB: ClaudeLocalDBReader

    @State private var selectedTab: DetailTab = .overview
    @State private var chartUse24HourTime: Bool
    @State private var showSession = true
    @State private var showWeekly = true
    @State private var shareAnchorView: NSView?
    @State private var hostingWindow: NSWindow?
    @State private var hasActivatedWindow = false
    @State private var shareErrorMessage = ""
    @State private var showShareError = false

    init(coordinator: MacAppCoordinator, history: UsageHistory, localDB: ClaudeLocalDBReader) {
        self.coordinator = coordinator
        self.history = history
        self.localDB = localDB
        _chartUse24HourTime = State(initialValue: coordinator.settings.use24HourTime)
    }

    var body: some View {
        VStack(spacing: 0) {
            windowHeader
            Divider().overlay(ClaudeCodeTheme.progressTrack)
            tabBar
            Divider().overlay(ClaudeCodeTheme.progressTrack)

            ScrollView {
                tabContent
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
            }
        }
        .background(ClaudeCodeTheme.background)
        .background(StatsWindowAccessor(window: $hostingWindow))
        .onChange(of: hostingWindow, initial: true) { _, window in
            activateWindowIfNeeded(window)
        }
        .task {
            // Load local stats on demand when the user opens the stats window
            await localDB.load()
        }
        .frame(minWidth: 900, minHeight: 780)
        .alert("Unable to Share Chart", isPresented: $showShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage)
        }
    }

    // MARK: - Window Header

    private var windowHeader: some View {
        HStack {
            Text("Tempo for Claude")
                .font(.title3.weight(.semibold))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            Spacer()
            if let email = coordinator.authState.accountEmail {
                Text(email)
                    .font(.callout)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(DetailTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(selectedTab == tab ? .subheadline.weight(.semibold) : .subheadline)
                        .foregroundStyle(selectedTab == tab ? ClaudeCodeTheme.accent : ClaudeCodeTheme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            selectedTab == tab
                                ? ClaudeCodeTheme.accentMuted
                                : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewTab
        case .activity:
            activityTab
        case .preferences:
            preferencesTab
        }
    }

    // MARK: - Overview Tab

    @ViewBuilder
    private var overviewTab: some View {
        if let usage = coordinator.poller.latestUsage {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 20) {
                    // Chart card
                    chartCardContainer(use24HourTime: chartUse24HourTime, usage: usage)

                    // 2-column card grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        sessionCard(usage: usage, now: context.date)
                        weeklyCard(usage: usage)
                        if let extra = usage.extraUsage, extra.isEnabled {
                            extraUsageCard(extra: extra)
                        }
                        burnStatusCard(usage: usage, now: context.date)
                    }
                }
            }
        } else {
            loadingView
        }
    }

    // Chart wrapped in card container
    @ViewBuilder
    private func chartCardContainer(use24HourTime: Bool, usage: UsageState) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            chartSection(use24HourTime: use24HourTime, usage: usage)
        }
        .padding(16)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    // Session card
    private func sessionCard(usage: UsageState, now: Date) -> some View {
        let sessionColor = UsageRingStyle.sessionColor(utilization: usage.utilization5h)

        return HStack(spacing: 0) {
            Rectangle()
                .fill(sessionColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TempoSingleRing(
                        progress: usage.utilization5h,
                        color: sessionColor
                    )
                    .frame(width: 64, height: 64)
                    Spacer()
                }
                Text("\(Int(usage.utilization5h * 100))%")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(sessionColor)
                Text(TimeFormatPolicy.sessionResetString(
                    resetAt: usage.resetAt5h,
                    now: now,
                    use24HourTime: chartUse24HourTime
                ))
                .font(.footnote)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Text("Session")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    // Weekly card
    private func weeklyCard(usage: UsageState) -> some View {
        let weeklyColor = UsageRingStyle.weeklyColor(utilization: usage.utilization7d)

        return HStack(spacing: 0) {
            Rectangle()
                .fill(weeklyColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TempoSingleRing(
                        progress: usage.utilization7d,
                        color: weeklyColor
                    )
                    .frame(width: 64, height: 64)
                    Spacer()
                }
                Text("\(Int(usage.utilization7d * 100))%")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(weeklyColor)
                Text(TimeFormatPolicy.weeklyResetString(
                    resetAt: usage.resetAt7d,
                    use24HourTime: chartUse24HourTime
                ))
                .font(.footnote)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Text("Weekly")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    // Extra Usage card
    private func extraUsageCard(extra: ExtraUsage) -> some View {
        let extraColor = UtilizationSeverity(utilization: (extra.utilization ?? 0) / 100.0).usageColor(normal: ClaudeCodeTheme.info)

        return HStack(spacing: 0) {
            Rectangle()
                .fill(extraColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                if let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                    Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    UsageProgressBar(
                        progress: (extra.utilization ?? 0) / 100.0,
                        color: extraColor
                    )
                }
                Text("Resets monthly")
                    .font(.footnote)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Text("Extra Usage")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    // Burn Status card
    private func burnStatusCard(usage: UsageState, now: Date) -> some View {
        let rate = burnRate(usage: usage, now: now)
        let onTrack = rate < 20
        let stripeColor: Color = onTrack ? ClaudeCodeTheme.success : ClaudeCodeTheme.warning

        return HStack(spacing: 0) {
            Rectangle()
                .fill(stripeColor)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(stripeColor)
                        .frame(width: 8, height: 8)
                    Text(onTrack ? "On track" : "High burn")
                        .font(.subheadline.bold())
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                }
                Text("\(String(format: "%.1f", rate))%/hr")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text(etaText(usage: usage, rate: rate, now: now))
                    .font(.footnote)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            .padding(16)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Activity Tab

    @ViewBuilder
    private var activityTab: some View {
        if let usage = coordinator.poller.latestUsage {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 24) {
                    // Insights summary
                    HStack(spacing: 16) {
                        warningCard(usage: usage, now: context.date)
                        subscriptionCard()
                    }

                    HStack(spacing: 16) {
                        compactStatCard(icon: "info.circle", title: "Avg Session", value: avgSession, subtitle: "average usage", color: ClaudeCodeTheme.textPrimary)
                        compactStatCard(icon: "calendar", title: "Avg Weekly", value: avgWeekly, subtitle: "average usage", color: ClaudeCodeTheme.textPrimary)
                        compactStatCard(icon: "exclamationmark.triangle", title: "High Usage", value: "\(highUsageDays)", subtitle: "days at 90%+", color: highUsageDays > 3 ? ClaudeCodeTheme.warning : ClaudeCodeTheme.textPrimary)
                        compactStatCard(icon: "arrow.up.right", title: "Peak", value: peakSession, subtitle: "highest session", color: ClaudeCodeTheme.textPrimary)
                    }

                    if localDB.needsAccessGrant {
                        localPermissionCard
                    } else {
                        // Heatmap card
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Usage Activity")
                                .font(.headline)
                                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                            if !localDB.isAvailable {
                                unavailableView("Activity data unavailable")
                            } else {
                                ActivityHeatmapView(dailyActivity: localDB.dailyActivity)
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(ClaudeCodeTheme.card)
                        .clipShape(.rect(cornerRadius: 12))

                        // Claude Code section card
                        claudeCodeStatsSection
                    }
                }
            }
        } else {
            loadingView
        }
    }

    private func warningCard(usage: UsageState, now: Date) -> some View {
        let rate = burnRate(usage: usage, now: now)
        let onTrack = rate < 20
        let remaining = 1.0 - usage.utilization5h
        let hoursToLimit: Double? = (!onTrack && rate > 0 && remaining > 0) ? remaining * 100.0 / rate : nil

        return HStack(alignment: .top, spacing: 16) {
            Image(systemName: onTrack ? "checkmark.circle" : "clock.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(onTrack ? ClaudeCodeTheme.success : ClaudeCodeTheme.error)

            VStack(alignment: .leading, spacing: 4) {
                Text(onTrack ? "Session Usage Normal" : "Session Limit Warning")
                    .font(.subheadline.bold())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)

                if let h = hoursToLimit {
                    Text("At current rate, you'll hit your session limit in less than \(etaString(hours: h))")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.error)
                } else if onTrack {
                    Text("Your usage is well within normal limits.")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                } else {
                    Text("You've reached your session limit.")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.error)
                }

                Text("Current rate: \(String(format: "%.1f", rate))%/hr")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func subscriptionCard() -> some View {
        let pct = avgWeeklyValue
        let message: String
        if history.snapshots.isEmpty {
            message = "Not enough data yet to evaluate subscription value."
        } else if pct < 0.30 {
            message = "Moderate usage. You have plenty of headroom in your weekly allocation."
        } else if pct < 0.70 {
            message = "Good utilization! You're making solid use of your subscription."
        } else {
            message = "High utilization. You're getting excellent value from your subscription."
        }

        return HStack(alignment: .top, spacing: 16) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 24))
                .foregroundStyle(ClaudeCodeTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Subscription Value")
                    .font(.subheadline.bold())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Text("Average weekly usage: \(avgWeekly)")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func compactStatCard(icon: String, title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    // MARK: - Preferences Tab

    private var preferencesTab: some View {
        PreferencesWindowView(coordinator: coordinator, standalone: false)
    }

    private func activateWindowIfNeeded(_ window: NSWindow?) {
        guard !hasActivatedWindow, let window else { return }
        hasActivatedWindow = true

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - Claude Code Stats Section

    private var claudeCodeStatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Text("Claude Code")
                    .font(.headline)
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Spacer()
                Text("7d")
                    .font(.caption2.bold())
                    .foregroundStyle(ClaudeCodeTheme.accent)
            }

            if !localDB.isAvailable {
                if localDB.needsAccessGrant {
                    grantAccessView
                } else {
                    unavailableView("Claude Code history unavailable - local DB not found")
                }
            } else {
                compactAggregateRow
                Divider().overlay(ClaudeCodeTheme.progressTrack)
                projectTable
            }
        }
        .padding(16)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    private var compactAggregateRow: some View {
        let models = localDB.modelUsage.isEmpty ? localDB.modelTokens7d : localDB.modelUsage.mapValues { $0.inputTokens + $0.outputTokens }

        let opus = models.filter { $0.key.contains("opus") }.values.reduce(0, +)
        let sonnet = models.filter { $0.key.contains("sonnet") }.values.reduce(0, +)
        let haiku = models.filter { $0.key.contains("haiku") }.values.reduce(0, +)

        let msgCount = localDB.projectStats.reduce(0) { $0 + $1.messages7d }
        let toolCount = localDB.projectStats.reduce(0) { $0 + $1.toolCalls7d }
        let sessionCount = localDB.projectStats.reduce(0) { $0 + $1.sessions7d }
        let costEquiv7d = localDB.projectStats.reduce(0.0) { $0 + $1.costEquiv7d }

        return VStack(alignment: .leading, spacing: 12) {
            // Main stats row
            HStack(spacing: 0) {
                statItem(icon: "bubble.left", label: "Messages", value: msgCount.formatted())
                    .frame(maxWidth: .infinity, alignment: .leading)
                statItem(icon: "wrench.and.screwdriver", label: "Tool Calls", value: toolCount.formatted())
                    .frame(maxWidth: .infinity, alignment: .leading)
                statItem(icon: "square.stack.3d.up", label: "Sessions", value: sessionCount.formatted())
                    .frame(maxWidth: .infinity, alignment: .leading)
                statItem(icon: "dollarsign.circle", label: "API Equiv.", value: costEquiv7d > 0 ? String(format: "$%.0f", costEquiv7d) : "-")
                    .frame(maxWidth: .infinity, alignment: .leading)
                statItem(icon: "network", label: "Subagents", value: localDB.totalSubagents.formatted())
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Model token breakdown row
            if opus > 0 || sonnet > 0 || haiku > 0 {
                Divider().overlay(ClaudeCodeTheme.progressTrack)
                HStack(spacing: 8) {
                    Text("Tokens")
                        .font(.caption2)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    if opus > 0 {
                        modelTokenPill(label: "Opus", value: formatTokens(opus), color: .purple)
                    }
                    if sonnet > 0 {
                        modelTokenPill(label: "Sonnet", value: formatTokens(sonnet), color: .orange)
                    }
                    if haiku > 0 {
                        modelTokenPill(label: "Haiku", value: formatTokens(haiku), color: .green)
                    }
                    Spacer()
                }
            }
        }
    }

    private func statItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
        }
    }

    private func modelTokenPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2.bold())
                .foregroundStyle(color)
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }

    private var projectTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Project")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Group {
                    Text("Sessions").frame(width: 80, alignment: .trailing)
                    Text("Messages").frame(width: 80, alignment: .trailing)
                    Text("Tools").frame(width: 80, alignment: .trailing)
                    Text("Tokens").frame(width: 80, alignment: .trailing)
                    Text("Cost").frame(width: 80, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            Divider().overlay(ClaudeCodeTheme.progressTrack)

            if localDB.projectStats.isEmpty {
                Text("No project data available")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .padding(.top, 8)
            } else {
                ForEach(localDB.projectStats.filter { $0.hasActivity7d }) { stat in
                    HStack {
                        Text(stat.displayName)
                            .font(.caption)
                            .foregroundStyle(ClaudeCodeTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Group {
                            Text(stat.sessions7d > 0 ? "\(stat.sessions7d)" : "-").frame(width: 80, alignment: .trailing)
                            Text(stat.messages7d > 0 ? stat.messages7d.formatted() : "-").frame(width: 80, alignment: .trailing)
                            Text(stat.toolCalls7d > 0 ? stat.toolCalls7d.formatted() : "-").frame(width: 80, alignment: .trailing)
                            Text(stat.totalTokens7d > 0 ? formatTokens(stat.totalTokens7d) : "-").frame(width: 80, alignment: .trailing)
                            Text(stat.costEquiv7d > 0 ? String(format: "$%.2f", stat.costEquiv7d) : "-").frame(width: 80, alignment: .trailing)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Chart Section

    @State private var timeRange: TimeRange = .hours5
    @State private var previousTimeRange: TimeRange = .hours5
    @State private var customStart: Date = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
    @State private var customEnd: Date = Calendar.current.startOfDay(for: Date())

    enum TimeRange: String, CaseIterable, Identifiable {
        case hours5 = "5 Hours"
        case hours24 = "24 Hours"
        case days7 = "7 Days"
        case days30 = "30 Days"
        case days90 = "90 Days"
        case custom = "Custom"
        var id: String { self.rawValue }
    }

    @ViewBuilder
    private func chartSection(use24HourTime: Bool, usage: UsageState) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 10) {
                    Text("Usage Over Time")
                        .font(.headline)
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)

                    if usage.isUsingExtraUsage {
                        extraUsageStatusChip(label: "Extra Usage Active")
                    }
                }
                Spacer()
                Menu {
                    ForEach(TimeRange.allCases) { range in
                        Button(range.rawValue) {
                            if range == .custom {
                                previousTimeRange = timeRange
                            }
                            timeRange = range
                        }
                    }
                } label: {
                    Text(timeRange.rawValue)
                }
                .menuStyle(.borderlessButton)
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .frame(width: 80)

                Button {
                    shareChartImage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canShareCurrentRange ? ClaudeCodeTheme.textSecondary : ClaudeCodeTheme.textSecondary.opacity(0.5))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .disabled(!canShareCurrentRange)
                .background(ShareAnchorView(anchorView: $shareAnchorView))
                .help(canShareCurrentRange ? "Share chart image" : "No chart data available for sharing")
            }

            if timeRange == .custom {
                HStack(spacing: 8) {
                    DatePicker("", selection: $customStart, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    Text("to")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    DatePicker("", selection: $customEnd, in: customStart..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    Button {
                        timeRange = previousTimeRange
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .onChange(of: customStart) { _, newStart in
                    if customEnd < newStart {
                        customEnd = newStart
                    }
                }
            }

            let visibleSnapshots = visibleSnapshotsForCurrentRange
            let sessionSnapshots = sessionSnapshotsForDisplay(from: visibleSnapshots)
            let sessionSegments = splitUsageSegments(
                sessionSnapshots,
                maxGap: maxGapForCurrentRange,
                value: \.utilization5h,
                extraUsage: \.isUsingExtraUsage5h
            )
            let weeklySegments = splitUsageSegments(
                visibleSnapshots,
                maxGap: maxGapForCurrentRange,
                value: \.utilization7d,
                extraUsage: \.isUsingExtraUsage7d
            )
            let xDomain = dateDomain()
            let sessionExtraUsageWindows = extraUsageWindows(
                in: sessionSnapshots,
                upperBound: xDomain.upperBound,
                extraUsage: \.isUsingExtraUsage5h
            )
            let weeklyExtraUsageWindows = extraUsageWindows(
                in: visibleSnapshots,
                upperBound: xDomain.upperBound,
                extraUsage: \.isUsingExtraUsage7d
            )
            let hasVisibleExtraUsage = visibleSnapshots.contains { $0.isUsingExtraUsage }

            if hasVisibleExtraUsage || usage.isUsingExtraUsage {
                Text("Dashed blue and orange marks billable Extra Usage after the included limit.")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }

            if visibleSnapshots.isEmpty {
                HStack {
                    Spacer()
                    Text("No history yet - check back after the next poll")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 60)
            } else {
                Chart {
                    if showSession {
                        ForEach(sessionExtraUsageWindows) { window in
                            RectangleMark(
                                xStart: .value("Extra Usage Start", window.start),
                                xEnd: .value("Extra Usage End", window.end),
                                yStart: .value("Extra Usage Min", 0),
                                yEnd: .value("Extra Usage Max", 105)
                            )
                            .foregroundStyle(ClaudeCodeTheme.info.opacity(0.10))
                        }
                    }

                    if showWeekly {
                        ForEach(weeklyExtraUsageWindows) { window in
                            RectangleMark(
                                xStart: .value("Weekly Extra Usage Start", window.start),
                                xEnd: .value("Weekly Extra Usage End", window.end),
                                yStart: .value("Weekly Extra Usage Min", 0),
                                yEnd: .value("Weekly Extra Usage Max", 105)
                            )
                            .foregroundStyle(ClaudeCodeTheme.error.opacity(0.07))
                        }
                    }

                    RuleMark(y: .value("Warning", 80))
                        .foregroundStyle(ClaudeCodeTheme.error.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    RuleMark(x: .value("Now", Date()))
                        .foregroundStyle(ClaudeCodeTheme.info.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    if showWeekly {
                        ForEach(visibleSnapshots) { snap in
                            AreaMark(
                                x: .value("Time", snap.date),
                                yStart: .value("Weekly Area Min", 0),
                                yEnd: .value("Weekly Area Max", snap.utilization7d * 100)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        ClaudeCodeTheme.error.opacity(0.16),
                                        ClaudeCodeTheme.error.opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }

                    if showSession {
                        ForEach(Array(sessionSegments.enumerated()), id: \.offset) { segmentIndex, segment in
                            let sessionSeriesKey = "session-\(segmentIndex)"
                            ForEach(segment.snapshots) { snap in
                                AreaMark(
                                    x: .value("Time", snap.date),
                                    yStart: .value("Session Area Min", 0),
                                    yEnd: .value("Session Area Max", snap.utilization5h * 100),
                                    series: .value("Series", sessionSeriesKey)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            ClaudeCodeTheme.info.opacity(segment.isUsingExtraUsage ? 0.22 : 0.34),
                                            ClaudeCodeTheme.info.opacity(segment.isUsingExtraUsage ? 0.04 : 0.08)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Time", snap.date),
                                    y: .value("Session", snap.utilization5h * 100),
                                    series: .value("Series", sessionSeriesKey)
                                )
                                .foregroundStyle(ClaudeCodeTheme.info)
                                .lineStyle(
                                    StrokeStyle(
                                        lineWidth: segment.isUsingExtraUsage ? 3 : 2.5,
                                        dash: segment.isUsingExtraUsage ? [7, 5] : []
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }
                    }
                    if showWeekly {
                        ForEach(visibleSnapshots) { snap in
                            LineMark(
                                x: .value("Time", snap.date),
                                y: .value("Weekly", snap.utilization7d * 100)
                            )
                            .foregroundStyle(ClaudeCodeTheme.error)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }

                        ForEach(Array(weeklySegments.enumerated()), id: \.offset) { segmentIndex, segment in
                            if segment.isUsingExtraUsage {
                                let weeklySeriesKey = "weekly-extra-\(segmentIndex)"
                                ForEach(segment.snapshots) { snap in
                                    LineMark(
                                        x: .value("Time", snap.date),
                                        y: .value("Weekly Extra Usage", snap.utilization7d * 100),
                                        series: .value("Series", weeklySeriesKey)
                                    )
                                    .foregroundStyle(ClaudeCodeTheme.error)
                                    .lineStyle(StrokeStyle(lineWidth: 3, dash: [7, 5]))
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))%")
                                    .font(.caption)
                                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    let customSpan = customEnd.timeIntervalSince(customStart)
                    if timeRange == .hours24 {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                            AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(chartHourAxisLabel(for: date, use24HourTime: use24HourTime))
                                }
                            }
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        }
                    } else if timeRange == .hours5 {
                        AxisMarks(values: .stride(by: .hour)) { value in
                            AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(chartHourAxisLabel(for: date, use24HourTime: use24HourTime))
                                }
                            }
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        }
                    } else if timeRange == .custom && customSpan <= 24 * 3600 {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                            AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(chartHourAxisLabel(for: date, use24HourTime: use24HourTime))
                                }
                            }
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        }
                    } else if timeRange == .custom && customSpan <= 7 * 24 * 3600 {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                            AxisValueLabel(format: .dateTime.month().day())
                                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        }
                    } else {
                        AxisMarks(preset: .aligned, values: .automatic) { value in
                            AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                            AxisValueLabel()
                                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        }
                    }
                }
                .chartYScale(domain: 0...105)
                .chartXScale(domain: xDomain)
                .frame(height: 220)
                .id("chart-time-format-\(use24HourTime)")
            }

            // Legend
            HStack(spacing: 24) {
                Spacer()
                legendToggle(label: "Session", color: ClaudeCodeTheme.info, isOn: $showSession)
                legendToggle(label: "Weekly", color: ClaudeCodeTheme.error, isOn: $showWeekly)
                if hasVisibleExtraUsage || usage.isUsingExtraUsage {
                    extraUsageLegendKey
                }
                Spacer()
                Button { exportCSV() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export CSV")
                    }
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(ClaudeCodeTheme.progressTrack))
                }
                .buttonStyle(.plain)
            }

            Text("Scroll to view earlier data")
                .font(.caption2)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .opacity(history.snapshots.count > 10 ? 1 : 0)
        }
    }

    private func chartHourAxisLabel(for date: Date, use24HourTime: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = use24HourTime
            ? Locale(identifier: "en_GB_POSIX")
            : Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = use24HourTime ? "HH:mm" : "h:mm a"
        return formatter.string(from: date)
    }

    private func filteredSnapshots() -> [UsageSnapshot] {
        let now = Date()
        let interval: TimeInterval
        switch timeRange {
        case .hours5: interval = 5 * 3600
        case .hours24: interval = 24 * 3600
        case .days7: interval = 7 * 24 * 3600
        case .days30: interval = 30 * 24 * 3600
        case .days90: interval = 90 * 24 * 3600
        case .custom:
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: customEnd) ?? customEnd
            return history.snapshots.filter { $0.date >= customStart && $0.date < endOfDay }
        }
        let cutoff = now.addingTimeInterval(-interval)
        return history.snapshots.filter { $0.date >= cutoff }
    }

    private var maxGapForCurrentRange: TimeInterval {
        switch timeRange {
        case .hours5, .hours24:
            return 90 * 60
        case .days7:
            return 3 * 3600
        case .days30:
            return 12 * 3600
        case .days90:
            return 24 * 3600
        case .custom:
            let customSpan = customEnd.timeIntervalSince(customStart)
            if customSpan <= 24 * 3600 { return 90 * 60 }
            if customSpan <= 7 * 24 * 3600 { return 3 * 3600 }
            if customSpan <= 30 * 24 * 3600 { return 12 * 3600 }
            return 24 * 3600
        }
    }

    private func sessionSnapshotsForDisplay(from snapshots: [UsageSnapshot]) -> [UsageSnapshot] {
        let sorted = snapshots.sorted(by: { $0.date < $1.date })
        guard sorted.count > 1 else { return sorted }

        let riseEpsilon = 0.005
        let visibleSessionRange: ArraySlice<UsageSnapshot>
        if let riseIndex = sorted.indices.dropFirst().first(where: { index in
            sorted[index].utilization5h - sorted[index - 1].utilization5h > riseEpsilon
        }) {
            let startIndex = max(0, riseIndex - 1)
            visibleSessionRange = sorted[startIndex...]
        } else {
            let maxSession = sorted.map(\.utilization5h).max() ?? 0
            guard maxSession > riseEpsilon else { return [] }
            visibleSessionRange = sorted[...]
        }

        let trimmed = trimTrailingIdleSessionSnapshots(Array(visibleSessionRange))
        return trimmed
    }

    private func trimTrailingIdleSessionSnapshots(_ snapshots: [UsageSnapshot]) -> [UsageSnapshot] {
        guard snapshots.count > 1 else { return snapshots }

        let epsilon = 0.0001
        var lastMeaningfulIndex = snapshots.count - 1

        while lastMeaningfulIndex > 0 {
            let current = snapshots[lastMeaningfulIndex]
            let previous = snapshots[lastMeaningfulIndex - 1]
            let sessionChanged = abs(current.utilization5h - previous.utilization5h) > epsilon
            let extraUsageChanged = current.isUsingExtraUsage5h != previous.isUsingExtraUsage5h

            if sessionChanged || extraUsageChanged || current.isUsingExtraUsage5h {
                break
            }
            lastMeaningfulIndex -= 1
        }

        return Array(snapshots[...lastMeaningfulIndex])
    }

    private func splitUsageSegments(
        _ snapshots: [UsageSnapshot],
        maxGap: TimeInterval,
        value: KeyPath<UsageSnapshot, Double>,
        extraUsage: KeyPath<UsageSnapshot, Bool>
    ) -> [SessionChartSegment] {
        guard !snapshots.isEmpty else { return [] }
        let sorted = snapshots.sorted(by: { $0.date < $1.date })
        var segments: [SessionChartSegment] = []
        var currentSegment: [UsageSnapshot] = [sorted[0]]
        let resetDropThreshold = 0.25

        for snapshot in sorted.dropFirst() {
            guard let last = currentSegment.last else { continue }
            let hasLargeGap = snapshot.date.timeIntervalSince(last.date) > maxGap
            let hasResetDrop = (last[keyPath: value] - snapshot[keyPath: value]) > resetDropThreshold
            if hasLargeGap || hasResetDrop {
                segments.append(
                    SessionChartSegment(
                        snapshots: currentSegment,
                        isUsingExtraUsage: currentSegment.first?[keyPath: extraUsage] ?? false
                    )
                )
                currentSegment = [snapshot]
            } else if snapshot[keyPath: extraUsage] != last[keyPath: extraUsage] {
                segments.append(
                    SessionChartSegment(
                        snapshots: currentSegment,
                        isUsingExtraUsage: currentSegment.first?[keyPath: extraUsage] ?? false
                    )
                )
                currentSegment = [last, snapshot]
            } else {
                currentSegment.append(snapshot)
            }
        }

        if !currentSegment.isEmpty {
            segments.append(
                SessionChartSegment(
                    snapshots: currentSegment,
                    isUsingExtraUsage: currentSegment.first?[keyPath: extraUsage] ?? false
                )
            )
        }
        return segments
    }

    private func meaningfulSnapshots(from snapshots: [UsageSnapshot]) -> [UsageSnapshot] {
        let sorted = snapshots.sorted(by: { $0.date < $1.date })
        guard sorted.count > 1 else { return sorted }

        let epsilon = 0.0001
        var lastMeaningfulIndex = sorted.count - 1

        while lastMeaningfulIndex > 0 {
            let current = sorted[lastMeaningfulIndex]
            let previous = sorted[lastMeaningfulIndex - 1]

            let sessionChanged = abs(current.utilization5h - previous.utilization5h) > epsilon
            let weeklyChanged = abs(current.utilization7d - previous.utilization7d) > epsilon
            let extraUsageChanged =
                current.isUsingExtraUsage5h != previous.isUsingExtraUsage5h
                || current.isUsingExtraUsage7d != previous.isUsingExtraUsage7d

            if sessionChanged || weeklyChanged || extraUsageChanged || current.isUsingExtraUsage {
                break
            }
            lastMeaningfulIndex -= 1
        }

        if lastMeaningfulIndex == sorted.count - 1 {
            return sorted
        }
        return Array(sorted[...lastMeaningfulIndex])
    }

    private func dateDomain() -> ClosedRange<Date> {
        let now = Date()
        let interval: TimeInterval
        switch timeRange {
        case .hours5: interval = 5 * 3600
        case .hours24: interval = 24 * 3600
        case .days7: interval = 7 * 24 * 3600
        case .days30: interval = 30 * 24 * 3600
        case .days90: interval = 90 * 24 * 3600
        case .custom:
            let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: customEnd) ?? customEnd
            return customStart...endOfDay
        }
        let cutoff = now.addingTimeInterval(-interval)
        return cutoff...now
    }

    private func extraUsageWindows(
        in snapshots: [UsageSnapshot],
        upperBound: Date,
        extraUsage: KeyPath<UsageSnapshot, Bool>
    ) -> [ExtraUsageWindow] {
        let sorted = snapshots.sorted(by: { $0.date < $1.date })
        guard !sorted.isEmpty else { return [] }

        var windows: [ExtraUsageWindow] = []
        var start: Date?
        var lastExtraDate: Date?

        for snapshot in sorted {
            if snapshot[keyPath: extraUsage] {
                start = start ?? snapshot.date
                lastExtraDate = snapshot.date
            } else if let rangeStart = start, let rangeEnd = lastExtraDate {
                windows.append(ExtraUsageWindow(start: rangeStart, end: max(rangeStart, rangeEnd)))
                start = nil
                lastExtraDate = nil
            }
        }

        if let rangeStart = start, let rangeEnd = lastExtraDate {
            windows.append(ExtraUsageWindow(start: rangeStart, end: max(rangeEnd, upperBound)))
        }

        return windows
    }

    private func legendToggle(label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn.wrappedValue ? color : ClaudeCodeTheme.textSecondary)
                    .font(.system(size: 14))
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    private var extraUsageLegendKey: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(
                    ClaudeCodeTheme.info,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .frame(width: 20, height: 8)
            Text("Extra Usage")
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
    }

    private func extraUsageStatusChip(label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(ClaudeCodeTheme.accentLight)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(ClaudeCodeTheme.accent.opacity(0.18))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(
                        ClaudeCodeTheme.accent.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                    )
            )
    }

    private var visibleSnapshotsForCurrentRange: [UsageSnapshot] {
        meaningfulSnapshots(from: filteredSnapshots())
    }

    private var canShareCurrentRange: Bool {
        !visibleSnapshotsForCurrentRange.isEmpty
    }

    // MARK: - Loading / Unavailable Views

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
                .tint(ClaudeCodeTheme.textSecondary)
            Text("Fetching usage…")
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    @ViewBuilder
    private var grantAccessView: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Folder access required")
                    .font(.caption.bold())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text("Grant read access to your ~/.claude folder to enable local statistics.")
                    .font(.caption2)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            Spacer()
            Button("Grant Access") {
                localDB.requestFolderAccess()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.vertical, 8)
    }

    private var localPermissionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark")
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Text("Local Claude Access")
                    .font(.headline)
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Spacer()
            }

            Text("Grant read access to your ~/.claude folder to enable both Usage Activity and Claude Code local statistics.")
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)

            grantAccessView
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }

    @ViewBuilder
    private func unavailableView(_ reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            Text(reason)
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func etaText(usage: UsageState, rate: Double, now: Date) -> String {
        let remaining = 1.0 - usage.utilization5h
        if rate > 0 && remaining > 0 && rate >= 20 {
            let hours = remaining * 100.0 / rate
            return "Limit in ~\(etaString(hours: hours))"
        }
        return TimeFormatPolicy.sessionResetString(
            resetAt: usage.resetAt5h,
            now: now,
            use24HourTime: chartUse24HourTime
        )
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func etaString(hours: Double) -> String {
        if hours >= 1 {
            let h = Int(hours)
            let mins = Int((hours - Double(h)) * 60)
            return mins > 0 ? "~\(h) hr \(mins) min" : "~\(h) hr"
        }
        let mins = Int(hours * 60)
        return mins > 0 ? "\(mins) min" : "< 1 min"
    }

    private func burnRate(usage: UsageState, now: Date) -> Double {
        let hoursUntilReset = max(0, usage.resetAt5h.timeIntervalSince(now) / 3600)
        let hoursElapsed = max(0.1, 5.0 - hoursUntilReset)
        return usage.utilization5h * 100.0 / hoursElapsed
    }

    private var avgSession: String {
        let values = history.snapshots.map(\.utilization5h)
        guard !values.isEmpty else { return "-" }
        return "\(Int(values.reduce(0, +) / Double(values.count) * 100))%"
    }

    private var avgWeekly: String {
        let values = history.snapshots.map(\.utilization7d)
        guard !values.isEmpty else { return "-" }
        return "\(Int(values.reduce(0, +) / Double(values.count) * 100))%"
    }

    private var avgWeeklyValue: Double {
        let values = history.snapshots.map(\.utilization7d)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private var peakSession: String {
        guard let peak = history.snapshots.map(\.utilization5h).max() else { return "-" }
        return "\(Int(peak * 100))%"
    }

    private var highUsageDays: Int {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: history.snapshots) { cal.startOfDay(for: $0.date) }
        return grouped.values.filter { ($0.map(\.utilization5h).max() ?? 0) >= 0.9 }.count
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "claude-usage-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "date,utilization5h,utilization7d,isUsingExtraUsage5h,isUsingExtraUsage7d\n"
        let fmt = ISO8601DateFormatter()
        for snap in history.snapshots {
            csv += "\(fmt.string(from: snap.date)),\(snap.utilization5h),\(snap.utilization7d),\(snap.isUsingExtraUsage5h),\(snap.isUsingExtraUsage7d)\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    private func shareChartImage() {
        do {
            let imageURL = try buildShareImageFileURL()
            presentSharingPicker(with: imageURL)
        } catch ShareError.noData {
            shareErrorMessage = "No chart data is available for the selected time range."
            showShareError = true
        } catch ShareError.unsupportedRenderer {
            shareErrorMessage = "Image sharing requires macOS 13 or newer."
            showShareError = true
        } catch ShareError.renderFailed {
            shareErrorMessage = "Could not render the chart image."
            showShareError = true
        } catch ShareError.encodingFailed {
            shareErrorMessage = "Could not encode the rendered image as PNG."
            showShareError = true
        } catch ShareError.writeFailed {
            shareErrorMessage = "Could not write the PNG file to a temporary location."
            showShareError = true
        } catch {
            shareErrorMessage = "An unexpected error occurred while preparing the share image."
            showShareError = true
        }
    }

    private func buildShareImageFileURL() throws -> URL {
        let snapshots = visibleSnapshotsForCurrentRange
        guard !snapshots.isEmpty else { throw ShareError.noData }
        guard #available(macOS 13.0, *) else { throw ShareError.unsupportedRenderer }

        let exportDate = Date()
        let selectedDomain = dateDomain()
        let cardView = StatsShareCardView(
            timeRangeLabel: timeRange.rawValue,
            xDomain: selectedDomain,
            maxGap: maxGapForCurrentRange,
            snapshots: snapshots,
            avgSessionLabel: avgSession,
            avgWeeklyLabel: avgWeekly,
            messagesLabel: localDB.projectStats.reduce(0) { $0 + $1.messages7d }.formatted(),
            sessionsLabel: localDB.projectStats.reduce(0) { $0 + $1.sessions7d }.formatted(),
            exportedAt: exportDate
        )
        .frame(width: 1060, height: 740)

        let renderer = ImageRenderer(content: cardView)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        guard let nsImage = renderer.nsImage else { throw ShareError.renderFailed }
        guard
            let tiffData = nsImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            throw ShareError.encodingFailed
        }

        let filename = "tempo-usage-stats-\(Int(exportDate.timeIntervalSince1970)).png"
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            try pngData.write(to: outputURL, options: .atomic)
            return outputURL
        } catch {
            throw ShareError.writeFailed
        }
    }

    private func presentSharingPicker(with imageURL: URL) {
        let picker = NSSharingServicePicker(items: [imageURL])
        if let anchorView = shareAnchorView {
            picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
            return
        }

        guard let windowView = NSApp.keyWindow?.contentView else {
            shareErrorMessage = "Could not determine where to present the share picker."
            showShareError = true
            return
        }
        picker.show(relativeTo: windowView.bounds, of: windowView, preferredEdge: .minY)
    }

    private enum ShareError: Error {
        case noData
        case unsupportedRenderer
        case renderFailed
        case encodingFailed
        case writeFailed
    }
}

// MARK: - ActivityHeatmapView

struct ActivityHeatmapView: View {
    let dailyActivity: [LocalDailyActivity]

    private let cellSize: CGFloat = 10
    private let gap: CGFloat = 2
    private let weekCount = 52

    private var countByDate: [String: Int] {
        Dictionary(uniqueKeysWithValues: dailyActivity.map { ($0.date, $0.sessionCount) })
    }

    private var maxCount: Int {
        max(1, dailyActivity.map(\.sessionCount).max() ?? 1)
    }

    private var weeks: [[Date]] {
        let today = Date()
        let cal = Calendar.current
        let totalDays = weekCount * 7
        let allDays = (0..<totalDays).compactMap {
            cal.date(byAdding: .day, value: $0 - (totalDays - 1), to: today)
        }
        return stride(from: 0, to: allDays.count, by: 7).map {
            Array(allDays[$0..<min($0 + 7, allDays.count)])
        }
    }

    var body: some View {
        let fmt = Self.dateFmt
        let byDate = countByDate
        let mx = maxCount
        let monthLabels = generateMonthLabels()

        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: gap) {
                Text(" ").frame(height: cellSize)
                Text("Mon").font(.system(size: 9)).foregroundStyle(ClaudeCodeTheme.textSecondary).frame(height: cellSize * 2 + gap)
                Text("Wed").font(.system(size: 9)).foregroundStyle(ClaudeCodeTheme.textSecondary).frame(height: cellSize * 2 + gap)
                Text("Fri").font(.system(size: 9)).foregroundStyle(ClaudeCodeTheme.textSecondary).frame(height: cellSize * 2 + gap)
            }
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(monthLabels) { label in
                        Text(label.text)
                            .font(.system(size: 10))
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                            .frame(width: CGFloat(label.weeksSpan) * (cellSize + gap), alignment: .leading)
                    }
                }

                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                                let count = byDate[fmt.string(from: date)] ?? 0
                                let intensity = Double(count) / Double(mx)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(count == 0
                                        ? ClaudeCodeTheme.ringTrackInner
                                        : ClaudeCodeTheme.accent.opacity(0.3 + intensity * 0.7))
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    struct MonthLabel: Identifiable {
        let id: Int
        let text: String
        let weeksSpan: Int
    }

    private func generateMonthLabels() -> [MonthLabel] {
        var labels: [MonthLabel] = []
        let cal = Calendar.current
        var currentMonth = -1
        var currentSpan = 0
        var currentMonthName = ""
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM"

        for week in weeks {
            guard let firstDay = week.first else { continue }
            let month = cal.component(.month, from: firstDay)
            if month != currentMonth {
                if currentSpan > 0 {
                    labels.append(MonthLabel(id: labels.count, text: currentMonthName, weeksSpan: currentSpan))
                }
                currentMonth = month
                currentMonthName = formatter.string(from: firstDay)
                currentSpan = 1
            } else {
                currentSpan += 1
            }
        }
        if currentSpan > 0 {
            labels.append(MonthLabel(id: labels.count, text: currentMonthName, weeksSpan: currentSpan))
        }
        return labels
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

// MARK: - StatsShareCardView (export only - retains its own visual style)

private struct StatsShareCardView: View {
    let timeRangeLabel: String
    let xDomain: ClosedRange<Date>
    let maxGap: TimeInterval
    let snapshots: [UsageSnapshot]
    let avgSessionLabel: String
    let avgWeeklyLabel: String
    let messagesLabel: String
    let sessionsLabel: String
    let exportedAt: Date

    private static let exportDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter
    }()

    private var sessionSnapshots: [UsageSnapshot] {
        sessionSnapshotsForDisplay(from: snapshots)
    }

    private var sessionSegments: [SessionChartSegment] {
        splitUsageSegments(
            sessionSnapshots,
            maxGap: maxGap,
            value: \.utilization5h,
            extraUsage: \.isUsingExtraUsage5h
        )
    }

    private var weeklySegments: [SessionChartSegment] {
        splitUsageSegments(
            snapshots,
            maxGap: maxGap,
            value: \.utilization7d,
            extraUsage: \.isUsingExtraUsage7d
        )
    }

    private var sessionExtraUsageWindows: [ExtraUsageWindow] {
        extraUsageWindows(in: sessionSnapshots, upperBound: xDomain.upperBound, extraUsage: \.isUsingExtraUsage5h)
    }

    private var weeklyExtraUsageWindows: [ExtraUsageWindow] {
        extraUsageWindows(in: snapshots, upperBound: xDomain.upperBound, extraUsage: \.isUsingExtraUsage7d)
    }

    var body: some View {
        let sessionColor = ClaudeCodeTheme.Usage.session
        let weeklyColor = ClaudeCodeTheme.Usage.weekly
        let extraUsageColor = ClaudeCodeTheme.Usage.critical

        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(ClaudeCodeTheme.background)

            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Tempo for Claude")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    }
                    Spacer()
                    Text(rangeLabel)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(timeRangeLabel)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)

                    Chart {
                        ForEach(sessionExtraUsageWindows) { window in
                            RectangleMark(
                                xStart: .value("Extra Usage Start", window.start),
                                xEnd: .value("Extra Usage End", window.end),
                                yStart: .value("Extra Usage Min", 0),
                                yEnd: .value("Extra Usage Max", 105)
                            )
                            .foregroundStyle(extraUsageColor.opacity(0.08))
                        }

                        ForEach(weeklyExtraUsageWindows) { window in
                            RectangleMark(
                                xStart: .value("Weekly Extra Usage Start", window.start),
                                xEnd: .value("Weekly Extra Usage End", window.end),
                                yStart: .value("Weekly Extra Usage Min", 0),
                                yEnd: .value("Weekly Extra Usage Max", 105)
                            )
                            .foregroundStyle(extraUsageColor.opacity(0.07))
                        }

                        RuleMark(y: .value("Warning", 80))
                            .foregroundStyle(ClaudeCodeTheme.Usage.warning.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 6]))

                        ForEach(snapshots) { snap in
                            AreaMark(
                                x: .value("Time", snap.date),
                                yStart: .value("Weekly Area Min", 0),
                                yEnd: .value("Weekly Area Max", snap.utilization7d * 100)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        weeklyColor.opacity(0.16),
                                        weeklyColor.opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }

                        ForEach(Array(sessionSegments.enumerated()), id: \.offset) { segmentIndex, segment in
                            let sessionSeriesKey = "session-\(segmentIndex)"
                            let segmentColor = segment.isUsingExtraUsage ? extraUsageColor : sessionColor
                            ForEach(segment.snapshots) { snap in
                                AreaMark(
                                    x: .value("Time", snap.date),
                                    yStart: .value("Session Area Min", 0),
                                    yEnd: .value("Session Area Max", snap.utilization5h * 100),
                                    series: .value("Series", sessionSeriesKey)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [
                                            segmentColor.opacity(segment.isUsingExtraUsage ? 0.22 : 0.34),
                                            segmentColor.opacity(segment.isUsingExtraUsage ? 0.04 : 0.08)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )

                                LineMark(
                                    x: .value("Time", snap.date),
                                    y: .value("Session", snap.utilization5h * 100),
                                    series: .value("Series", sessionSeriesKey)
                                )
                                .foregroundStyle(segmentColor)
                                .lineStyle(
                                    StrokeStyle(
                                        lineWidth: segment.isUsingExtraUsage ? 4.5 : 4,
                                        dash: segment.isUsingExtraUsage ? [10, 6] : []
                                    )
                                )
                                .interpolationMethod(.catmullRom)
                            }
                        }

                        ForEach(snapshots) { snap in
                            LineMark(
                                x: .value("Time", snap.date),
                                y: .value("Weekly", snap.utilization7d * 100)
                            )
                            .foregroundStyle(weeklyColor)
                            .lineStyle(StrokeStyle(lineWidth: 4))
                            .interpolationMethod(.catmullRom)
                        }

                        ForEach(Array(weeklySegments.enumerated()), id: \.offset) { segmentIndex, segment in
                            if segment.isUsingExtraUsage {
                                let weeklySeriesKey = "weekly-extra-\(segmentIndex)"
                                ForEach(segment.snapshots) { snap in
                                    LineMark(
                                        x: .value("Time", snap.date),
                                        y: .value("Weekly Extra Usage", snap.utilization7d * 100),
                                        series: .value("Series", weeklySeriesKey)
                                    )
                                    .foregroundStyle(extraUsageColor)
                                    .lineStyle(StrokeStyle(lineWidth: 4.5, dash: [10, 6]))
                                    .interpolationMethod(.catmullRom)
                                }
                            }
                        }
                    }
                    .chartLegend(.hidden)
                    .chartYScale(domain: 0...105)
                    .chartXScale(domain: xDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine()
                                .foregroundStyle(ClaudeCodeTheme.ringTrack)
                            AxisValueLabel()
                                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine()
                                .foregroundStyle(ClaudeCodeTheme.ringTrack)
                            AxisValueLabel {
                                if let value = value.as(Double.self) {
                                    Text("\(Int(value))%")
                                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                                }
                            }
                        }
                    }
                    .frame(height: 320)

                    HStack(spacing: 26) {
                        legendItem(color: sessionColor, title: "Session")
                        if snapshots.contains(where: { $0.isUsingExtraUsage }) {
                            legendItem(color: extraUsageColor, title: "Extra Usage", dashed: true)
                        }
                        legendItem(color: weeklyColor, title: "Weekly")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(ClaudeCodeTheme.surface)
                )

                HStack(spacing: 16) {
                    summaryCard(title: "Avg Session", value: avgSessionLabel)
                    summaryCard(title: "Avg Weekly", value: avgWeeklyLabel)
                    summaryCard(title: "Messages", value: messagesLabel)
                    summaryCard(title: "Sessions", value: sessionsLabel)
                }

                HStack {
                    Text("Tempo for Claude")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ClaudeCodeTheme.background)
                    Spacer()
                    Text(Self.exportDateFormatter.string(from: exportedAt))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(ClaudeCodeTheme.background.opacity(0.82))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(ClaudeCodeTheme.highlight)
                )
            }
            .padding(28)
        }
    }

    private var rangeLabel: String {
        "\(Self.compactDateFormatter.string(from: xDomain.lowerBound)) - \(Self.compactDateFormatter.string(from: xDomain.upperBound))"
    }

    private static let compactDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter
    }()

    private func sessionSnapshotsForDisplay(from snapshots: [UsageSnapshot]) -> [UsageSnapshot] {
        let sorted = snapshots.sorted(by: { $0.date < $1.date })
        guard sorted.count > 1 else { return sorted }

        let riseEpsilon = 0.005
        let visibleSessionRange: ArraySlice<UsageSnapshot>
        if let riseIndex = sorted.indices.dropFirst().first(where: { index in
            sorted[index].utilization5h - sorted[index - 1].utilization5h > riseEpsilon
        }) {
            let startIndex = max(0, riseIndex - 1)
            visibleSessionRange = sorted[startIndex...]
        } else {
            let maxSession = sorted.map(\.utilization5h).max() ?? 0
            guard maxSession > riseEpsilon else { return [] }
            visibleSessionRange = sorted[...]
        }

        return trimTrailingIdleSessionSnapshots(Array(visibleSessionRange))
    }

    private func splitUsageSegments(
        _ snapshots: [UsageSnapshot],
        maxGap: TimeInterval,
        value: KeyPath<UsageSnapshot, Double>,
        extraUsage: KeyPath<UsageSnapshot, Bool>
    ) -> [SessionChartSegment] {
        guard !snapshots.isEmpty else { return [] }
        let sorted = snapshots.sorted(by: { $0.date < $1.date })
        var result: [SessionChartSegment] = []
        var current: [UsageSnapshot] = [sorted[0]]
        let resetDropThreshold = 0.25

        for snapshot in sorted.dropFirst() {
            guard let previous = current.last else { continue }
            let hasLargeGap = snapshot.date.timeIntervalSince(previous.date) > maxGap
            let hasResetDrop = (previous[keyPath: value] - snapshot[keyPath: value]) > resetDropThreshold
            if hasLargeGap || hasResetDrop {
                result.append(
                    SessionChartSegment(
                        snapshots: current,
                        isUsingExtraUsage: current.first?[keyPath: extraUsage] ?? false
                    )
                )
                current = [snapshot]
            } else if snapshot[keyPath: extraUsage] != previous[keyPath: extraUsage] {
                result.append(
                    SessionChartSegment(
                        snapshots: current,
                        isUsingExtraUsage: current.first?[keyPath: extraUsage] ?? false
                    )
                )
                current = [previous, snapshot]
            } else {
                current.append(snapshot)
            }
        }

        if !current.isEmpty {
            result.append(
                SessionChartSegment(
                    snapshots: current,
                    isUsingExtraUsage: current.first?[keyPath: extraUsage] ?? false
                )
            )
        }
        return result
    }

    private func trimTrailingIdleSessionSnapshots(_ snapshots: [UsageSnapshot]) -> [UsageSnapshot] {
        guard snapshots.count > 1 else { return snapshots }

        let epsilon = 0.0001
        var lastMeaningfulIndex = snapshots.count - 1

        while lastMeaningfulIndex > 0 {
            let current = snapshots[lastMeaningfulIndex]
            let previous = snapshots[lastMeaningfulIndex - 1]
            let sessionChanged = abs(current.utilization5h - previous.utilization5h) > epsilon
            let extraUsageChanged = current.isUsingExtraUsage5h != previous.isUsingExtraUsage5h

            if sessionChanged || extraUsageChanged || current.isUsingExtraUsage5h {
                break
            }
            lastMeaningfulIndex -= 1
        }

        return Array(snapshots[...lastMeaningfulIndex])
    }

    @ViewBuilder
    private func legendItem(color: Color, title: String, dashed: Bool = false) -> some View {
        HStack(spacing: 8) {
            if dashed {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(color, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .frame(width: 18, height: 8)
            } else {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            }
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
        }
    }

    private func extraUsageWindows(
        in snapshots: [UsageSnapshot],
        upperBound: Date,
        extraUsage: KeyPath<UsageSnapshot, Bool>
    ) -> [ExtraUsageWindow] {
        let sorted = snapshots.sorted(by: { $0.date < $1.date })
        guard !sorted.isEmpty else { return [] }

        var windows: [ExtraUsageWindow] = []
        var start: Date?
        var lastExtraDate: Date?

        for snapshot in sorted {
            if snapshot[keyPath: extraUsage] {
                start = start ?? snapshot.date
                lastExtraDate = snapshot.date
            } else if let rangeStart = start, let rangeEnd = lastExtraDate {
                windows.append(ExtraUsageWindow(start: rangeStart, end: max(rangeStart, rangeEnd)))
                start = nil
                lastExtraDate = nil
            }
        }

        if let rangeStart = start, let rangeEnd = lastExtraDate {
            windows.append(ExtraUsageWindow(start: rangeStart, end: max(rangeEnd, upperBound)))
        }

        return windows
    }

    @ViewBuilder
    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            Text(value)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(ClaudeCodeTheme.highlight)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(ClaudeCodeTheme.surface)
        )
    }
}

// MARK: - ShareAnchorView

private struct ShareAnchorView: NSViewRepresentable {
    @Binding var anchorView: NSView?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            anchorView = view
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            anchorView = nsView
        }
    }
}

private struct StatsWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            window = nsView.window
        }
    }
}
