import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

// MARK: - StatsDetailView

struct StatsDetailView: View {
    let coordinator: MacAppCoordinator
    let history: UsageHistory
    let localDB: ClaudeLocalDBReader

    @State private var showSession = true
    @State private var showWeekly = true

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(ClaudeTheme.progressTrack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let usage = coordinator.poller.latestUsage {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            chartSection
                            Divider().overlay(ClaudeTheme.progressTrack)
                            heatmapSection
                            Divider().overlay(ClaudeTheme.progressTrack)
                            insightsSection(usage: usage, now: context.date)
                            Divider().overlay(ClaudeTheme.progressTrack)
                            claudeCodeStatsSection
                        }
                    } else {
                        loadingView
                    }
                }
            }
        }
        .background(ClaudeTheme.background)
        .preferredColorScheme(.dark)
        .frame(minWidth: 850, minHeight: 750)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Usage History")
                .font(.headline)
                .foregroundStyle(ClaudeTheme.textPrimary)
            Spacer()
            if let email = coordinator.authState.accountEmail {
                Text(email)
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
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
    private var chartSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Usage Over Time")
                    .font(.headline)
                    .foregroundStyle(ClaudeTheme.textPrimary)
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
                .foregroundStyle(ClaudeTheme.textSecondary)
                .frame(width: 80)
            }

            if timeRange == .custom {
                HStack(spacing: 8) {
                    DatePicker("", selection: $customStart, displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    Text("to")
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                    DatePicker("", selection: $customEnd, in: customStart..., displayedComponents: .date)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    Button {
                        timeRange = previousTimeRange
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(ClaudeTheme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
                .onChange(of: customStart) { _, newStart in
                    if customEnd < newStart {
                        customEnd = newStart
                    }
                }
            }

            if history.snapshots.isEmpty {
                HStack {
                    Spacer()
                    Text("No history yet — check back after the next poll")
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 60)
            } else {
                let visibleSnapshots = filteredSnapshots().sorted(by: { $0.date < $1.date })
                
                Chart {
                    // 80% warning threshold
                    RuleMark(y: .value("Warning", 80))
                        .foregroundStyle(Color(red: 0.8, green: 0.3, blue: 0.2).opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // "Now" vertical marker
                    RuleMark(x: .value("Now", Date()))
                        .foregroundStyle(Color(red: 0.16, green: 0.50, blue: 0.95).opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Now")
                                .font(.system(size: 9))
                                .foregroundStyle(ClaudeTheme.textSecondary)
                        }

                    if showSession {
                        ForEach(visibleSnapshots) { snap in
                            LineMark(
                                x: .value("Time", snap.date),
                                y: .value("Session", snap.utilization5h * 100)
                            )
                            .foregroundStyle(by: .value("Type", "Session"))
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    if showWeekly {
                        ForEach(visibleSnapshots) { snap in
                            LineMark(
                                x: .value("Time", snap.date),
                                y: .value("Weekly", snap.utilization7d * 100)
                            )
                            .foregroundStyle(by: .value("Type", "Weekly"))
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
                .chartForegroundStyleScale([
                    "Session": Color(red: 0.16, green: 0.50, blue: 0.95),
                    "Weekly": Color(red: 0.8, green: 0.3, blue: 0.2)
                ])
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine().foregroundStyle(ClaudeTheme.progressTrack)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text("\(Int(v))%")
                                    .font(.caption)
                                    .foregroundStyle(ClaudeTheme.textSecondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    let customSpan = customEnd.timeIntervalSince(customStart)
                    if timeRange == .hours24 {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                            AxisGridLine().foregroundStyle(ClaudeTheme.progressTrack)
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                                .foregroundStyle(ClaudeTheme.textSecondary)
                        }
                    } else if timeRange == .hours5 {
                        AxisMarks(values: .stride(by: .hour)) { _ in
                            AxisGridLine().foregroundStyle(ClaudeTheme.progressTrack)
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                                .foregroundStyle(ClaudeTheme.textSecondary)
                        }
                    } else if timeRange == .custom && customSpan <= 24 * 3600 {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { _ in
                            AxisGridLine().foregroundStyle(ClaudeTheme.progressTrack)
                            AxisValueLabel(format: .dateTime.hour(.defaultDigits(amPM: .omitted)).minute())
                                .foregroundStyle(ClaudeTheme.textSecondary)
                        }
                    } else if timeRange == .custom && customSpan <= 7 * 24 * 3600 {
                        AxisMarks(values: .stride(by: .day)) { _ in
                            AxisGridLine().foregroundStyle(ClaudeTheme.progressTrack)
                            AxisValueLabel(format: .dateTime.month().day())
                                .foregroundStyle(ClaudeTheme.textSecondary)
                        }
                    } else {
                        AxisMarks(preset: .aligned, values: .automatic) { value in
                            AxisGridLine().foregroundStyle(ClaudeTheme.progressTrack)
                            AxisValueLabel()
                                .foregroundStyle(ClaudeTheme.textSecondary)
                        }
                    }
                }
                .chartYScale(domain: 0...105)
                .chartXScale(domain: dateDomain())
                .frame(height: 220)
            }

            // Legend
            HStack(spacing: 24) {
                Spacer()
                legendToggle(label: "Session", color: Color(red: 0.16, green: 0.50, blue: 0.95), isOn: $showSession)
                legendToggle(label: "Weekly", color: Color(red: 0.8, green: 0.3, blue: 0.2), isOn: $showWeekly)
                Spacer()
                Button { exportCSV() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export CSV")
                    }
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 6).stroke(ClaudeTheme.progressTrack))
                }
                .buttonStyle(.plain)
            }

            Text("Scroll to view earlier data")
                .font(.caption2)
                .foregroundStyle(ClaudeTheme.textSecondary)
                .opacity(history.snapshots.count > 10 ? 1 : 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 20)
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

    private func legendToggle(label: String, color: Color, isOn: Binding<Bool>) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn.wrappedValue ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn.wrappedValue ? color : ClaudeTheme.textSecondary)
                    .font(.system(size: 14))
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(ClaudeTheme.textPrimary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Heatmap Section

    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Usage Activity")
                .font(.headline)
                .foregroundStyle(ClaudeTheme.textPrimary)

            if !localDB.isAvailable {
                unavailableView("Activity data unavailable")
            } else {
                ActivityHeatmapView(dailyActivity: localDB.dailyActivity)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    // MARK: - Insights Section

    private func insightsSection(usage: UsageState, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Insights")
                .font(.headline)
                .foregroundStyle(ClaudeTheme.textPrimary)

            HStack(spacing: 16) {
                warningCard(usage: usage, now: now)
                subscriptionCard()
            }

            HStack(spacing: 16) {
                compactStatCard(icon: "info.circle", title: "Avg Session", value: avgSession, subtitle: "average usage", color: Color(red: 0.8, green: 0.3, blue: 0.2))
                compactStatCard(icon: "calendar", title: "Avg Weekly", value: avgWeekly, subtitle: "average usage", color: ClaudeTheme.textPrimary)
                compactStatCard(icon: "exclamationmark.triangle", title: "High Usage", value: "\(highUsageDays)", subtitle: "days at 90%+", color: Color(red: 0.8, green: 0.3, blue: 0.2))
                compactStatCard(icon: "arrow.up.right", title: "Peak", value: peakSession, subtitle: "highest session", color: Color(red: 0.8, green: 0.3, blue: 0.2))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    private func warningCard(usage: UsageState, now: Date) -> some View {
        let rate = burnRate(usage: usage, now: now)
        let onTrack = rate < 20
        let hoursToLimit: Double? = (!onTrack && rate > 0) ? (1.0 - usage.utilization5h) * 100.0 / rate : nil

        return HStack(alignment: .top, spacing: 16) {
            Image(systemName: onTrack ? "checkmark.circle" : "clock.badge.exclamationmark")
                .font(.system(size: 24))
                .foregroundStyle(onTrack ? Color.green : Color(red: 0.8, green: 0.3, blue: 0.2))

            VStack(alignment: .leading, spacing: 4) {
                Text(onTrack ? "Session Usage Normal" : "Weekly Limit Warning")
                    .font(.subheadline.bold())
                    .foregroundStyle(ClaudeTheme.textPrimary)

                if let h = hoursToLimit {
                    Text("At current rate, you'll hit your weekly limit in less than \(etaString(hours: h))")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.8, green: 0.3, blue: 0.2))
                } else {
                    Text("Your usage is well within normal limits.")
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                }

                Text("Current rate: \(String(format: "%.1f", rate))%/hr")
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // No explicit background block in UI? The user screenshots show an empty/no background or very subtle surface.
        // I will stick to ClaudeTheme.background for these specific ones, to look like just text over background
    }

    private func subscriptionCard() -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 24))
                .foregroundStyle(ClaudeTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Subscription Value")
                    .font(.subheadline.bold())
                    .foregroundStyle(ClaudeTheme.textPrimary)
                Text("Good utilization! You're making solid use of your subscription.")
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
                Text("Average weekly usage: \(avgWeekly)")
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactStatCard(icon: String, title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(ClaudeTheme.textSecondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Claude Code Stats Section

    private var claudeCodeStatsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(ClaudeTheme.textSecondary)
                Text("Claude Code")
                    .font(.headline)
                    .foregroundStyle(ClaudeTheme.textPrimary)
            }

            if !localDB.isAvailable {
                unavailableView("Claude Code history unavailable — local DB not found")
            } else {
                compactAggregateRow
                projectTable
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    private var compactAggregateRow: some View {
        let models = localDB.modelUsage.isEmpty ? localDB.modelTokens7d : localDB.modelUsage.mapValues { $0.inputTokens + $0.outputTokens }
        
        let opus = models.filter { $0.key.contains("opus") }.values.reduce(0, +)
        let sonnet = models.filter { $0.key.contains("sonnet") }.values.reduce(0, +)
        let haiku = models.filter { $0.key.contains("haiku") }.values.reduce(0, +)

        let msgCount = localDB.totalMessages > 0 ? localDB.totalMessages : localDB.messages7d
        let sessionCount = localDB.totalSessions > 0 ? localDB.totalSessions : localDB.sessions7d

        return HStack(spacing: 0) {
            statItem(icon: "bubble.left", label: "Messages", value: msgCount.formatted())
                .frame(maxWidth: .infinity, alignment: .leading)
            statItem(icon: "wrench.and.screwdriver", label: "Tool Calls", value: localDB.toolCalls7d.formatted())
                .frame(maxWidth: .infinity, alignment: .leading)
            statItem(icon: "square.stack.3d.up", label: "Sessions", value: sessionCount.formatted())
                .frame(maxWidth: .infinity, alignment: .leading)
            statItem(icon: "dollarsign.circle", label: "API Equiv.", value: computeCostEquiv())
                .frame(maxWidth: .infinity, alignment: .leading)
            statItem(icon: "network", label: "Subagents", value: localDB.totalSubagents.formatted())
                .frame(maxWidth: .infinity, alignment: .leading)

            if opus > 0 { 
                modelTokenVStack("Opus", value: formatTokens(opus), color: Color.purple)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if sonnet > 0 { 
                modelTokenVStack("Sonnet", value: formatTokens(sonnet), color: Color.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if haiku > 0 { 
                modelTokenVStack("Haiku", value: formatTokens(haiku), color: Color.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 8)
    }

    private func computeCostEquiv() -> String {
        // Simple heuristic for Anthropic API equivalent costs
        // Sonnet 3.5: $3/M in, $15/M out.  Opus 3: $15/M in, $75/M out. Haiku 3.5: $1/M in, $5/M out.
        var totalCost: Double = 0.0
        for (model, usage) in localDB.modelUsage {
            let isIn = Double(usage.inputTokens) / 1_000_000.0
            let isOut = Double(usage.outputTokens) / 1_000_000.0
            
            if model.contains("opus") {
                totalCost += (isIn * 15.0) + (isOut * 75.0)
            } else if model.contains("sonnet") {
                totalCost += (isIn * 3.0) + (isOut * 15.0)
            } else if model.contains("haiku") {
                totalCost += (isIn * 1.0) + (isOut * 5.0)
            }
        }
        if totalCost == 0.0 { return "—" }
        return String(format: "$%.0f", totalCost)
    }

    private func statItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(ClaudeTheme.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.subheadline.bold())
                    .foregroundStyle(ClaudeTheme.textPrimary)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(ClaudeTheme.textSecondary)
            }
        }
    }

    private func modelTokenVStack(_ label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(color)
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(ClaudeTheme.textPrimary)
        }
    }

    private var projectTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Project")
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Group {
                    Text("Sessions").frame(width: 80, alignment: .trailing)
                    Text("Messages").frame(width: 80, alignment: .trailing)
                    Text("Tools").frame(width: 80, alignment: .trailing)
                    Text("Tokens").frame(width: 80, alignment: .trailing)
                    Text("Cost").frame(width: 80, alignment: .trailing)
                }
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)
            }
            Divider().overlay(ClaudeTheme.progressTrack)

            if localDB.projectStats.isEmpty {
                Text("No project data available")
                    .font(.caption)
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .padding(.top, 8)
            } else {
                ForEach(localDB.projectStats) { stat in
                    HStack {
                        Text(stat.displayName)
                            .font(.caption)
                            .foregroundStyle(ClaudeTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Group {
                            Text("\(stat.sessionCount)").frame(width: 80, alignment: .trailing)
                            Text("—").frame(width: 80, alignment: .trailing)
                            Text("—").frame(width: 80, alignment: .trailing)
                            Text("—").frame(width: 80, alignment: .trailing)
                            Text("—").frame(width: 80, alignment: .trailing)
                        }
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(ClaudeTheme.textPrimary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Loading / Unavailable Views

    private var loadingView: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
                .tint(ClaudeTheme.textSecondary)
            Text("Fetching usage…")
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }

    @ViewBuilder
    private func unavailableView(_ reason: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(ClaudeTheme.textSecondary)
            Text(reason)
                .font(.caption)
                .foregroundStyle(ClaudeTheme.textSecondary)
            Spacer()
        }
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func etaString(hours: Double) -> String {
        hours < 1 ? "\(Int(hours * 60)) min" : String(format: "%.1f hr", hours)
    }

    private func burnRate(usage: UsageState, now: Date) -> Double {
        let hoursUntilReset = max(0, usage.resetAt5h.timeIntervalSince(now) / 3600)
        let hoursElapsed = max(0.1, 5.0 - hoursUntilReset)
        return usage.utilization5h * 100.0 / hoursElapsed
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "claude-usage-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "date,utilization5h,utilization7d\n"
        let fmt = ISO8601DateFormatter()
        for snap in history.snapshots {
            csv += "\(fmt.string(from: snap.date)),\(snap.utilization5h),\(snap.utilization7d)\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    // Derived stats
    private var avgSession: String {
        let values = history.snapshots.map(\.utilization5h)
        guard !values.isEmpty else { return "—" }
        return "\(Int(values.reduce(0, +) / Double(values.count) * 100))%"
    }

    private var avgWeekly: String {
        let values = history.snapshots.map(\.utilization7d)
        guard !values.isEmpty else { return "—" }
        return "\(Int(values.reduce(0, +) / Double(values.count) * 100))%"
    }

    private var peakSession: String {
        guard let peak = history.snapshots.map(\.utilization5h).max() else { return "—" }
        return "\(Int(peak * 100))%"
    }

    private var highUsageDays: Int {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: history.snapshots) { cal.startOfDay(for: $0.date) }
        return grouped.values.filter { ($0.map(\.utilization5h).max() ?? 0) >= 0.9 }.count
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
            // Day Labels
            VStack(spacing: gap) {
                Text(" ").frame(height: cellSize) // For Month row height
                Text("Mon").font(.system(size: 9)).foregroundStyle(ClaudeTheme.textSecondary).frame(height: cellSize * 2 + gap)
                Text("Wed").font(.system(size: 9)).foregroundStyle(ClaudeTheme.textSecondary).frame(height: cellSize * 2 + gap)
                Text("Fri").font(.system(size: 9)).foregroundStyle(ClaudeTheme.textSecondary).frame(height: cellSize * 2 + gap)
            }
            .padding(.top, 14)

            VStack(alignment: .leading, spacing: 4) {
                // Month labels
                HStack(spacing: 0) {
                    ForEach(monthLabels, id: \.text) { label in
                        Text(label.text)
                            .font(.system(size: 10))
                            .foregroundStyle(ClaudeTheme.textSecondary)
                            .frame(width: CGFloat(label.weeksSpan) * (cellSize + gap), alignment: .leading)
                    }
                }

                // Grid
                HStack(alignment: .top, spacing: gap) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: gap) {
                            ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                                let count = byDate[fmt.string(from: date)] ?? 0
                                let intensity = Double(count) / Double(mx)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(count == 0
                                        ? Color.white.opacity(0.05)
                                        : Color(red: 0.8, green: 0.3, blue: 0.2).opacity(0.3 + intensity * 0.7))
                                    .frame(width: cellSize, height: cellSize)
                            }
                        }
                    }
                }
            }
        }
    }

    struct MonthLabel {
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
                    labels.append(MonthLabel(text: currentMonthName, weeksSpan: currentSpan))
                }
                currentMonth = month
                currentMonthName = formatter.string(from: firstDay)
                currentSpan = 1
            } else {
                currentSpan += 1
            }
        }
        if currentSpan > 0 {
            labels.append(MonthLabel(text: currentMonthName, weeksSpan: currentSpan))
        }
        return labels
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}
