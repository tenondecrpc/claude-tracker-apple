import SwiftUI
import Charts

struct ActivityTabView: View {
    @Bindable var store: IOSAppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                controlsCard

                if store.filteredHistorySnapshots.isEmpty {
                    emptyStateCard
                } else if !store.showSessionSeries && !store.showWeeklySeries {
                    statusCard(
                        title: "No series selected",
                        subtitle: "Enable at least one metric to display chart data.",
                        icon: "line.3.horizontal.decrease.circle.fill",
                        color: ClaudeCodeTheme.warning
                    )
                } else {
                    chartCard
                    summaryCard
                }

                if store.isHistoryStaleWhileUsageFresh {
                    statusCard(
                        title: "History is stale",
                        subtitle: "Live dashboard data is fresh, but history has not updated recently.",
                        icon: "clock.badge.exclamationmark.fill",
                        color: ClaudeCodeTheme.warning
                    )
                }

                if let historyReadError = store.historyReadError {
                    statusCard(
                        title: "History Read Error",
                        subtitle: historyReadError,
                        icon: "xmark.octagon.fill",
                        color: ClaudeCodeTheme.error
                    )
                }
            }
            .padding(16)
        }
        .background(ClaudeCodeTheme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Activity")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            Text("Historical trend from iCloud usage-history.json")
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
    }

    private var controlsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Range", selection: $store.historyRange) {
                    ForEach(UsageHistoryRange.allCases, id: \.self) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    Toggle("Session", isOn: $store.showSessionSeries)
                        .tint(ClaudeCodeTheme.info)
                    Toggle("Weekly", isOn: $store.showWeeklySeries)
                        .tint(ClaudeCodeTheme.error)
                    Toggle("24-hour time", isOn: $store.use24HourTime)
                        .tint(ClaudeCodeTheme.accent)
                }
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            }
        }
    }

    private var chartCard: some View {
        card {
            Chart {
                if store.showWeeklySeries {
                    ForEach(chartSnapshots) { snapshot in
                        AreaMark(
                            x: .value("Time", snapshot.date),
                            yStart: .value("Weekly Min", 0),
                            yEnd: .value("Weekly Max", UsageHistoryTransformer.boundedPercent(snapshot.utilization7d))
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

                if store.showSessionSeries {
                    ForEach(Array(sessionSegments.enumerated()), id: \.offset) { index, segment in
                        let seriesKey = "session-area-\(index)"
                        ForEach(segment) { snapshot in
                            AreaMark(
                                x: .value("Time", snapshot.date),
                                yStart: .value("Session Min", 0),
                                yEnd: .value("Session Max", UsageHistoryTransformer.boundedPercent(snapshot.utilization5h)),
                                series: .value("Series", seriesKey)
                            )
                            .interpolationMethod(.linear)
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        ClaudeCodeTheme.info.opacity(0.34),
                                        ClaudeCodeTheme.info.opacity(0.08)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                        }
                    }
                }

                RuleMark(y: .value("Warning", 80))
                    .foregroundStyle(ClaudeCodeTheme.error.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                if store.historyRange.isHourBased {
                    RuleMark(x: .value("Now", Date()))
                        .foregroundStyle(ClaudeCodeTheme.info.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }

                if store.showWeeklySeries {
                    ForEach(chartSnapshots) { snapshot in
                        LineMark(
                            x: .value("Time", snapshot.date),
                            y: .value("Weekly", UsageHistoryTransformer.boundedPercent(snapshot.utilization7d)),
                            series: .value("Metric", "Weekly")
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(by: .value("Metric", "Weekly"))
                    }
                }

                if store.showSessionSeries {
                    ForEach(Array(sessionSegments.enumerated()), id: \.offset) { index, segment in
                        let seriesKey = "session-line-\(index)"
                        ForEach(segment) { snapshot in
                            LineMark(
                                x: .value("Time", snapshot.date),
                                y: .value("Session", UsageHistoryTransformer.boundedPercent(snapshot.utilization5h)),
                                series: .value("Series", seriesKey)
                            )
                            .interpolationMethod(.catmullRom)
                            .lineStyle(StrokeStyle(lineWidth: 2.5))
                            .foregroundStyle(by: .value("Metric", "Session"))
                        }
                    }
                }
            }
            .frame(height: 250)
            .chartYScale(domain: 0...105)
            .chartXScale(domain: chartXDomain)
            .chartForegroundStyleScale([
                "Session": ClaudeCodeTheme.info,
                "Weekly": ClaudeCodeTheme.error
            ])
            .chartXAxis {
                if store.historyRange == .last5Hours {
                    AxisMarks(values: .stride(by: .hour)) { value in
                        AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                        AxisTick().foregroundStyle(ClaudeCodeTheme.border)
                        AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 12)) {
                            if let date = value.as(Date.self) {
                                Text(chartXAxisLabel(for: date))
                                    .font(.caption2)
                                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                            }
                        }
                    }
                } else if store.historyRange == .last24Hours {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                        AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                        AxisTick().foregroundStyle(ClaudeCodeTheme.border)
                        AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 12)) {
                            if let date = value.as(Date.self) {
                                Text(chartXAxisLabel(for: date))
                                    .font(.caption2)
                                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                            }
                        }
                    }
                } else {
                    AxisMarks(values: .stride(by: .day)) { value in
                        AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                        AxisTick().foregroundStyle(ClaudeCodeTheme.border)
                        AxisValueLabel(collisionResolution: .greedy(minimumSpacing: 12)) {
                            if let date = value.as(Date.self) {
                                Text(chartXAxisLabel(for: date))
                                    .font(.caption2)
                                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                            }
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0, 25, 50, 75, 100]) { value in
                    AxisGridLine().foregroundStyle(ClaudeCodeTheme.progressTrack)
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))%")
                                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        }
                    }
                }
            }
            .chartPlotStyle { plotArea in
                plotArea
                    .background(ClaudeCodeTheme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(ClaudeCodeTheme.border.opacity(0.45), lineWidth: 1)
                    )
            }
        }
    }

    private var summaryCard: some View {
        let filtered = store.filteredHistorySnapshots
        let avg5h = UsageHistoryTransformer.boundedPercent(UsageHistoryTransformer.averageUtilization5h(filtered))
        let avg7d = UsageHistoryTransformer.boundedPercent(UsageHistoryTransformer.averageUtilization7d(filtered))

        return card {
            HStack(spacing: 12) {
                statPill(title: "Avg Session", value: "\(Int(avg5h.rounded()))%", color: ClaudeCodeTheme.info)
                statPill(title: "Avg Weekly", value: "\(Int(avg7d.rounded()))%", color: ClaudeCodeTheme.error)
                statPill(title: "Points", value: "\(filtered.count)", color: ClaudeCodeTheme.highlight)
            }
        }
    }

    private var emptyStateCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Label("No activity history yet", systemImage: "tray")
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    .font(.headline)
                Text("Keep Tempo running on Mac. History will appear after iCloud sync writes usage snapshots.")
                    .font(.subheadline)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)

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
            }
        }
    }

    private func statPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudeCodeTheme.surface)
        .clipShape(.rect(cornerRadius: 12))
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

    private var chartSnapshots: [UsageHistorySnapshot] {
        store.filteredHistorySnapshots.sorted { $0.date < $1.date }
    }

    private var sessionSegments: [[UsageHistorySnapshot]] {
        Self.splitOnReset(chartSnapshots, value: \.utilization5h)
    }

    private static func splitOnReset(
        _ snapshots: [UsageHistorySnapshot],
        value: KeyPath<UsageHistorySnapshot, Double>,
        resetDropThreshold: Double = 0.25
    ) -> [[UsageHistorySnapshot]] {
        guard !snapshots.isEmpty else { return [] }
        var segments: [[UsageHistorySnapshot]] = []
        var current: [UsageHistorySnapshot] = [snapshots[0]]
        for snapshot in snapshots.dropFirst() {
            if let last = current.last,
               last[keyPath: value] - snapshot[keyPath: value] > resetDropThreshold {
                segments.append(current)
                current = [snapshot]
            } else {
                current.append(snapshot)
            }
        }
        if !current.isEmpty { segments.append(current) }
        return segments
    }

    private var chartXDomain: ClosedRange<Date> {
        let now = Date()
        return now.addingTimeInterval(-store.historyRange.duration)...now
    }

    private func chartXAxisLabel(for date: Date) -> String {
        switch store.historyRange {
        case .last5Hours, .last24Hours:
            let formatter = DateFormatter()
            formatter.locale = store.use24HourTime
                ? Locale(identifier: "en_GB_POSIX")
                : Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = store.use24HourTime ? "HH" : "ha"
            return formatter.string(from: date).lowercased()
        case .last7Days:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "d MMM"
            return formatter.string(from: date)
        }
    }
}
