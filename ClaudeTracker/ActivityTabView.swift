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

                HStack(spacing: 12) {
                    Toggle("5H Session", isOn: $store.showSessionSeries)
                        .tint(ClaudeCodeTheme.info)
                    Toggle("7D Weekly", isOn: $store.showWeeklySeries)
                        .tint(ClaudeCodeTheme.error)
                }
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            }
        }
    }

    private var chartCard: some View {
        card {
            Chart {
                if store.showSessionSeries {
                    ForEach(chartSnapshots) { snapshot in
                        LineMark(
                            x: .value("Time", snapshot.date),
                            y: .value("5H Session", UsageHistoryTransformer.boundedPercent(snapshot.utilization5h)),
                            series: .value("Metric", "5H Session")
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(by: .value("Metric", "5H Session"))
                    }
                }

                if store.showWeeklySeries {
                    ForEach(chartSnapshots) { snapshot in
                        LineMark(
                            x: .value("Time", snapshot.date),
                            y: .value("7D Weekly", UsageHistoryTransformer.boundedPercent(snapshot.utilization7d)),
                            series: .value("Metric", "7D Weekly")
                        )
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .foregroundStyle(by: .value("Metric", "7D Weekly"))
                    }
                }

                RuleMark(y: .value("Warning", 80))
                    .foregroundStyle(ClaudeCodeTheme.error.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))

                RuleMark(y: .value("Max", 100))
                    .foregroundStyle(ClaudeCodeTheme.border.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
            .frame(height: 250)
            .chartYScale(domain: 0...105)
            .chartXScale(domain: chartXDomain)
            .chartForegroundStyleScale([
                "5H Session": ClaudeCodeTheme.info,
                "7D Weekly": ClaudeCodeTheme.error
            ])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5))
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
                statPill(title: "Avg 5H", value: "\(Int(avg5h.rounded()))%", color: ClaudeCodeTheme.info)
                statPill(title: "Avg 7D", value: "\(Int(avg7d.rounded()))%", color: ClaudeCodeTheme.error)
                statPill(title: "Points", value: "\(filtered.count)", color: ClaudeCodeTheme.highlight)
            }
        }
    }

    private var emptyStateCard: some View {
        card {
            VStack(alignment: .leading, spacing: 8) {
                Label("No activity history yet", systemImage: "tray")
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    .font(.headline)
                Text("Keep ClaudeTracker running on Mac. History will appear after iCloud sync writes usage snapshots.")
                    .font(.subheadline)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
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

    private var chartXDomain: ClosedRange<Date> {
        guard let first = chartSnapshots.first?.date, let last = chartSnapshots.last?.date else {
            let now = Date()
            return now.addingTimeInterval(-3600)...now
        }
        guard first < last else {
            return first.addingTimeInterval(-1800)...first.addingTimeInterval(1800)
        }
        let span = last.timeIntervalSince(first)
        let padding = max(span * 0.02, 60)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }
}
