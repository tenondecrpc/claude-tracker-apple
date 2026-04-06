import SwiftUI
import Charts
import AppKit
import UniformTypeIdentifiers

// MARK: - StatsDetailView

struct StatsDetailView: View {
    let coordinator: MacAppCoordinator
    let history: UsageHistory
    let localDB: ClaudeLocalDBReader

    @State private var chartUse24HourTime: Bool
    @State private var showSession = true
    @State private var showWeekly = true
    @State private var shareAnchorView: NSView?
    @State private var shareErrorMessage = ""
    @State private var showShareError = false
    @State private var showSettings = false

    init(coordinator: MacAppCoordinator, history: UsageHistory, localDB: ClaudeLocalDBReader) {
        self.coordinator = coordinator
        self.history = history
        self.localDB = localDB
        _chartUse24HourTime = State(initialValue: coordinator.settings.use24HourTime)
    }

    var body: some View {
        let use24HourTime = chartUse24HourTime

        VStack(spacing: 0) {
            header
            Divider().overlay(ClaudeTheme.progressTrack)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let usage = coordinator.poller.latestUsage {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            chartSection(use24HourTime: use24HourTime)
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
        .alert("Unable to Share Chart", isPresented: $showShareError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareErrorMessage)
        }
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
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showSettings, arrowEdge: .top) {
                settingsPopover
                    .frame(width: 430)
                    .padding(16)
                    .background(ClaudeTheme.background)
                    .preferredColorScheme(.dark)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private var settingsPopover: some View {
        @Bindable var settings = coordinator.settings

        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.headline)
                .foregroundStyle(ClaudeTheme.textPrimary)
                .padding(.bottom, 14)

            Divider().overlay(ClaudeTheme.progressTrack)

            settingsToggleRow(
                icon: "power",
                title: "Launch at Login",
                subtitle: coordinator.launchAtLoginManager.helperMessage ?? "Start app when you log in",
                isOn: Binding(
                    get: { coordinator.launchAtLoginManager.isEnabled },
                    set: { coordinator.setLaunchAtLoginEnabled($0) }
                ),
                isDisabled: !coordinator.launchAtLoginManager.isSupportedInstallLocation
            )

            Divider().overlay(ClaudeTheme.progressTrack)

            settingsToggleRow(
                icon: "percent",
                title: "Show Percentage in Menu Bar",
                subtitle: "Display session usage percentage next to the icon",
                isOn: $settings.showPercentageInMenuBar
            )

            Divider().overlay(ClaudeTheme.progressTrack)

            settingsToggleRow(
                icon: "clock.arrow.2.circlepath",
                title: "24-Hour Time",
                subtitle: chartUse24HourTime ? "Times shown as 14:30" : "Times shown as 02:30 PM",
                isOn: Binding(
                    get: { chartUse24HourTime },
                    set: { newValue in
                        chartUse24HourTime = newValue
                        settings.use24HourTime = newValue
                    }
                )
            )

            Divider().overlay(ClaudeTheme.progressTrack)

            settingsToggleRow(
                icon: "dot.radiowaves.left.and.right",
                title: "Service Status Monitoring",
                subtitle: "Show Claude service status in the menu bar icon",
                isOn: $settings.serviceStatusMonitoring
            )

            Divider().overlay(ClaudeTheme.progressTrack)

            settingsToggleRow(
                icon: "icloud",
                title: "Sync History via iCloud",
                subtitle: "Sync usage history across your Macs",
                isOn: $settings.syncHistoryViaICloud
            )
        }
    }

    @ViewBuilder
    private func settingsToggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isDisabled: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color(red: 0.16, green: 0.50, blue: 0.95))
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isDisabled ? ClaudeTheme.textSecondary : ClaudeTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(ClaudeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(ClaudeTheme.accent)
                .disabled(isDisabled)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 2)
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
    private func chartSection(use24HourTime: Bool) -> some View {
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

                Button {
                    shareChartImage()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(canShareCurrentRange ? ClaudeTheme.textSecondary : ClaudeTheme.textSecondary.opacity(0.5))
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

            let visibleSnapshots = visibleSnapshotsForCurrentRange
            let sessionSnapshots = sessionSnapshotsForDisplay(from: visibleSnapshots)
            let sessionSegments = splitSessionSegments(sessionSnapshots, maxGap: maxGapForCurrentRange)

            if visibleSnapshots.isEmpty {
                HStack {
                    Spacer()
                    Text("No history yet — check back after the next poll")
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                    Spacer()
                }
                .padding(.vertical, 60)
            } else {
                Chart {
                    // 80% warning threshold
                    RuleMark(y: .value("Warning", 80))
                        .foregroundStyle(Color(red: 0.8, green: 0.3, blue: 0.2).opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                    // "Now" vertical marker
                    RuleMark(x: .value("Now", Date()))
                        .foregroundStyle(Color(red: 0.16, green: 0.50, blue: 0.95).opacity(0.4))
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
                                        Color(red: 0.8, green: 0.3, blue: 0.2).opacity(0.16),
                                        Color(red: 0.8, green: 0.3, blue: 0.2).opacity(0.02)
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
                            ForEach(segment) { snap in
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
                                            Color(red: 0.16, green: 0.50, blue: 0.95).opacity(0.34),
                                            Color(red: 0.16, green: 0.50, blue: 0.95).opacity(0.08)
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
                                .foregroundStyle(Color(red: 0.16, green: 0.50, blue: 0.95))
                                .lineStyle(StrokeStyle(lineWidth: 2.5))
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
                            .foregroundStyle(Color(red: 0.8, green: 0.3, blue: 0.2))
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                }
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
                        AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                            AxisGridLine().foregroundStyle(ClaudeTheme.progressTrack)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(chartHourAxisLabel(for: date, use24HourTime: use24HourTime))
                                }
                            }
                                .foregroundStyle(ClaudeTheme.textSecondary)
                        }
                    } else if timeRange == .hours5 {
                        AxisMarks(values: .stride(by: .hour)) { value in
                            AxisGridLine().foregroundStyle(ClaudeTheme.progressTrack)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(chartHourAxisLabel(for: date, use24HourTime: use24HourTime))
                                }
                            }
                                .foregroundStyle(ClaudeTheme.textSecondary)
                        }
                    } else if timeRange == .custom && customSpan <= 24 * 3600 {
                        AxisMarks(values: .stride(by: .hour, count: 3)) { value in
                            AxisGridLine().foregroundStyle(ClaudeTheme.progressTrack)
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(chartHourAxisLabel(for: date, use24HourTime: use24HourTime))
                                }
                            }
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
                .id("chart-time-format-\(use24HourTime)")
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

            if sessionChanged {
                break
            }
            lastMeaningfulIndex -= 1
        }

        return Array(snapshots[...lastMeaningfulIndex])
    }

    private func splitSessionSegments(_ snapshots: [UsageSnapshot], maxGap: TimeInterval) -> [[UsageSnapshot]] {
        guard !snapshots.isEmpty else { return [] }
        let sorted = snapshots.sorted(by: { $0.date < $1.date })
        var segments: [[UsageSnapshot]] = []
        var currentSegment: [UsageSnapshot] = [sorted[0]]
        let resetDropThreshold = 0.25

        for snapshot in sorted.dropFirst() {
            guard let last = currentSegment.last else { continue }
            let hasLargeGap = snapshot.date.timeIntervalSince(last.date) > maxGap
            let hasResetDrop = (last.utilization5h - snapshot.utilization5h) > resetDropThreshold
            if hasLargeGap || hasResetDrop {
                segments.append(currentSegment)
                currentSegment = [snapshot]
            } else {
                currentSegment.append(snapshot)
            }
        }

        if !currentSegment.isEmpty {
            segments.append(currentSegment)
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

            if sessionChanged || weeklyChanged {
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

    private var visibleSnapshotsForCurrentRange: [UsageSnapshot] {
        meaningfulSnapshots(from: filteredSnapshots())
    }

    private var canShareCurrentRange: Bool {
        !visibleSnapshotsForCurrentRange.isEmpty
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
        let remaining = 1.0 - usage.utilization5h
        let hoursToLimit: Double? = (!onTrack && rate > 0 && remaining > 0) ? remaining * 100.0 / rate : nil

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
                } else if onTrack {
                    Text("Your usage is well within normal limits.")
                        .font(.caption)
                        .foregroundStyle(ClaudeTheme.textSecondary)
                } else {
                    Text("You've reached your session limit.")
                        .font(.caption)
                        .foregroundStyle(Color(red: 0.8, green: 0.3, blue: 0.2))
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
                .foregroundStyle(ClaudeTheme.textSecondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("Subscription Value")
                    .font(.subheadline.bold())
                    .foregroundStyle(ClaudeTheme.textPrimary)
                Text(message)
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
                Text("7 days")
                    .font(.caption.bold())
                    .foregroundStyle(ClaudeTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ClaudeTheme.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
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

        let msgCount = localDB.projectStats.reduce(0) { $0 + $1.messages7d }
        let toolCount = localDB.projectStats.reduce(0) { $0 + $1.toolCalls7d }
        let sessionCount = localDB.projectStats.reduce(0) { $0 + $1.sessions7d }
        let costEquiv7d = localDB.projectStats.reduce(0.0) { $0 + $1.costEquiv7d }

        return HStack(spacing: 0) {
            statItem(icon: "bubble.left", label: "Messages", value: msgCount.formatted())
                .frame(maxWidth: .infinity, alignment: .leading)
            statItem(icon: "wrench.and.screwdriver", label: "Tool Calls", value: toolCount.formatted())
                .frame(maxWidth: .infinity, alignment: .leading)
            statItem(icon: "square.stack.3d.up", label: "Sessions", value: sessionCount.formatted())
                .frame(maxWidth: .infinity, alignment: .leading)
            statItem(icon: "dollarsign.circle", label: "API Equiv.", value: costEquiv7d > 0 ? String(format: "$%.0f", costEquiv7d) : "—")
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
                ForEach(localDB.projectStats.filter { $0.hasActivity7d }) { stat in
                    HStack {
                        Text(stat.displayName)
                            .font(.caption)
                            .foregroundStyle(ClaudeTheme.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Group {
                            Text(stat.sessions7d > 0 ? "\(stat.sessions7d)" : "—").frame(width: 80, alignment: .trailing)
                            Text(stat.messages7d > 0 ? stat.messages7d.formatted() : "—").frame(width: 80, alignment: .trailing)
                            Text(stat.toolCalls7d > 0 ? stat.toolCalls7d.formatted() : "—").frame(width: 80, alignment: .trailing)
                            Text(stat.totalTokens7d > 0 ? formatTokens(stat.totalTokens7d) : "—").frame(width: 80, alignment: .trailing)
                            Text(stat.costEquiv7d > 0 ? String(format: "$%.2f", stat.costEquiv7d) : "—").frame(width: 80, alignment: .trailing)
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

        let filename = "claude-usage-stats-\(Int(exportDate.timeIntervalSince1970)).png"
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

    private var avgWeeklyValue: Double {
        let values = history.snapshots.map(\.utilization7d)
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
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

    private var sessionSegments: [[UsageSnapshot]] {
        splitSessionSegments(sessionSnapshots, maxGap: maxGap)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(Color(red: 0.08, green: 0.09, blue: 0.12))

            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Usage For Claude")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    Text(rangeLabel)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text(timeRangeLabel)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)

                    Chart {
                        RuleMark(y: .value("Warning", 80))
                            .foregroundStyle(Color(red: 0.8, green: 0.3, blue: 0.2).opacity(0.45))
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
                                        Color(red: 0.8, green: 0.3, blue: 0.2).opacity(0.16),
                                        Color(red: 0.8, green: 0.3, blue: 0.2).opacity(0.02)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }

                        ForEach(Array(sessionSegments.enumerated()), id: \.offset) { segmentIndex, segment in
                            let sessionSeriesKey = "session-\(segmentIndex)"
                            ForEach(segment) { snap in
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
                                            Color(red: 0.16, green: 0.50, blue: 0.95).opacity(0.34),
                                            Color(red: 0.16, green: 0.50, blue: 0.95).opacity(0.08)
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
                                .foregroundStyle(Color(red: 0.16, green: 0.50, blue: 0.95))
                                .lineStyle(StrokeStyle(lineWidth: 4))
                                .interpolationMethod(.catmullRom)
                            }
                        }

                        ForEach(snapshots) { snap in
                            LineMark(
                                x: .value("Time", snap.date),
                                y: .value("Weekly", snap.utilization7d * 100)
                            )
                            .foregroundStyle(Color(red: 0.8, green: 0.3, blue: 0.2))
                            .lineStyle(StrokeStyle(lineWidth: 4))
                            .interpolationMethod(.catmullRom)
                        }
                    }
                    .chartLegend(.hidden)
                    .chartYScale(domain: 0...105)
                    .chartXScale(domain: xDomain)
                    .chartXAxis {
                        AxisMarks(values: .automatic) { _ in
                            AxisGridLine()
                                .foregroundStyle(Color.white.opacity(0.12))
                            AxisValueLabel()
                                .foregroundStyle(Color.white.opacity(0.58))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                            AxisGridLine()
                                .foregroundStyle(Color.white.opacity(0.12))
                            AxisValueLabel {
                                if let value = value.as(Double.self) {
                                    Text("\(Int(value))%")
                                        .foregroundStyle(Color.white.opacity(0.58))
                                }
                            }
                        }
                    }
                    .frame(height: 320)

                    HStack(spacing: 26) {
                        legendItem(color: Color(red: 0.16, green: 0.50, blue: 0.95), title: "Session")
                        legendItem(color: Color(red: 0.8, green: 0.3, blue: 0.2), title: "Weekly")
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )

                HStack(spacing: 16) {
                    summaryCard(title: "Avg Session", value: avgSessionLabel)
                    summaryCard(title: "Avg Weekly", value: avgWeeklyLabel)
                    summaryCard(title: "Messages", value: messagesLabel)
                    summaryCard(title: "Sessions", value: sessionsLabel)
                }

                HStack {
                    Text("Usage For Claude")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(Self.exportDateFormatter.string(from: exportedAt))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(red: 0.78, green: 0.42, blue: 0.31))
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

    private func splitSessionSegments(_ snapshots: [UsageSnapshot], maxGap: TimeInterval) -> [[UsageSnapshot]] {
        guard !snapshots.isEmpty else { return [] }
        let sorted = snapshots.sorted(by: { $0.date < $1.date })
        var result: [[UsageSnapshot]] = []
        var current: [UsageSnapshot] = [sorted[0]]
        let resetDropThreshold = 0.25

        for snapshot in sorted.dropFirst() {
            guard let previous = current.last else { continue }
            let hasLargeGap = snapshot.date.timeIntervalSince(previous.date) > maxGap
            let hasResetDrop = (previous.utilization5h - snapshot.utilization5h) > resetDropThreshold
            if hasLargeGap || hasResetDrop {
                result.append(current)
                current = [snapshot]
            } else {
                current.append(snapshot)
            }
        }

        if !current.isEmpty {
            result.append(current)
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

            if sessionChanged {
                break
            }
            lastMeaningfulIndex -= 1
        }

        return Array(snapshots[...lastMeaningfulIndex])
    }

    @ViewBuilder
    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.9))
        }
    }

    @ViewBuilder
    private func summaryCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.72))
            Text(value)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Color(red: 0.95, green: 0.56, blue: 0.44))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }
}

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
