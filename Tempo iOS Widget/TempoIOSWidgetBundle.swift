import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

private struct TempoIOSEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetUsageSnapshot?
    let isPreview: Bool
}

// MARK: - Provider

private struct TempoIOSProvider: TimelineProvider {
    func placeholder(in context: Context) -> TempoIOSEntry {
        TempoIOSEntry(date: .now, snapshot: .placeholder, isPreview: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TempoIOSEntry) -> Void) {
        if context.isPreview {
            completion(TempoIOSEntry(date: .now, snapshot: .placeholder, isPreview: true))
            return
        }
        completion(TempoIOSEntry(date: .now, snapshot: currentSnapshot(), isPreview: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TempoIOSEntry>) -> Void) {
        let entry: TempoIOSEntry
        if context.isPreview {
            entry = TempoIOSEntry(date: .now, snapshot: .placeholder, isPreview: true)
        } else {
            entry = TempoIOSEntry(date: .now, snapshot: currentSnapshot(), isPreview: false)
        }
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func currentSnapshot() -> WidgetUsageSnapshot? {
        TempoWidgetSnapshotStore.read(platform: .iOS)
    }
}

// MARK: - Widget Bundle

@main
struct TempoIOSWidgetBundle: WidgetBundle {
    var body: some Widget {
        TempoIOSRingWidget()
        TempoIOSSummaryWidget()
        TempoIOSCompactWidget()
    }
}

// MARK: - Widgets

private struct TempoIOSRingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TempoWidgetKind.iOSRing, provider: TempoIOSProvider()) { entry in
            TempoIOSRingWidgetView(entry: entry)
        }
        .configurationDisplayName("Tempo Usage")
        .description("Current Claude usage with a dual ring.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct TempoIOSSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TempoWidgetKind.iOSSummary, provider: TempoIOSProvider()) { entry in
            TempoIOSSummaryWidgetView(entry: entry)
        }
        .configurationDisplayName("Tempo Summary")
        .description("Current session and weekly usage in a wide summary.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct TempoIOSCompactWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TempoWidgetKind.iOSCompact, provider: TempoIOSProvider()) { entry in
            TempoIOSCompactWidgetView(entry: entry)
        }
        .configurationDisplayName("Tempo Compact")
        .description("A compact numeric view of your current usage.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Widget Views

private struct TempoIOSRingWidgetView: View {
    let entry: TempoIOSEntry

    var body: some View {
        TempoIOSWidgetChrome(snapshot: entry.snapshot, route: .dashboard, emptySubtitle: "Open Tempo on your iPhone", isPreview: entry.isPreview) { snapshot in
            VStack(alignment: .leading, spacing: 10) {
                header(snapshot: snapshot, title: "Current Session")

                Spacer(minLength: 0)

                TempoIOSDualRing(
                    sessionProgress: snapshot.utilization5h,
                    weeklyProgress: snapshot.utilization7d
                )
                .frame(maxWidth: .infinity, maxHeight: 92)

                Spacer(minLength: 0)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        Text(TempoWidgetFormatting.percentString(snapshot.utilization7d))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(ClaudeCodeTheme.info)
                    }
                    Spacer()
                    Text(TempoWidgetFormatting.freshnessLabel(snapshot))
                        .font(.caption2)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                }
            }
        }
    }

    private func header(snapshot: WidgetUsageSnapshot, title: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                if snapshot.isDoubleLimitPromoActive {
                    Text("2x promo")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(ClaudeCodeTheme.warning)
                }
            }
            Spacer()
            if let badge = TempoWidgetFormatting.statusBadge(snapshot) {
                TempoIOSStatusBadge(text: badge)
            }
        }
    }
}

private struct TempoIOSSummaryWidgetView: View {
    let entry: TempoIOSEntry

    var body: some View {
        TempoIOSWidgetChrome(snapshot: entry.snapshot, route: .dashboard, emptySubtitle: "Open Tempo to start syncing from your Mac", isPreview: entry.isPreview) { snapshot in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Usage for Claude")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(ClaudeCodeTheme.textPrimary)
                        Text("Live sync from Mac")
                            .font(.caption)
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    }
                    Spacer()
                    if let badge = TempoWidgetFormatting.statusBadge(snapshot) {
                        TempoIOSStatusBadge(text: badge)
                    }
                }

                TempoIOSMetricRow(
                    title: "Current Session",
                    value: TempoWidgetFormatting.percentString(snapshot.utilization5h),
                    subtitle: TempoWidgetFormatting.sessionResetString(snapshot),
                    progress: snapshot.utilization5h,
                    color: ClaudeCodeTheme.accent
                )

                TempoIOSMetricRow(
                    title: "Weekly Limit",
                    value: TempoWidgetFormatting.percentString(snapshot.utilization7d),
                    subtitle: TempoWidgetFormatting.weeklyResetString(snapshot),
                    progress: snapshot.utilization7d,
                    color: ClaudeCodeTheme.info
                )

                if snapshot.hasExtraUsageSummary {
                    HStack {
                        Text("Extra Usage")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        Spacer()
                        Text("\(ExtraUsage.formatUSD(snapshot.extraUsageUsedAmountUSD ?? 0)) / \(ExtraUsage.formatUSD(snapshot.extraUsageLimitAmountUSD ?? 0))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    }
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.caption2)
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        Text("Updated \(TempoWidgetFormatting.freshnessLabel(snapshot))")
                            .font(.caption2)
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    }
                }
            }
        }
    }
}

private struct TempoIOSCompactWidgetView: View {
    let entry: TempoIOSEntry

    var body: some View {
        TempoIOSWidgetChrome(snapshot: entry.snapshot, route: .dashboard, emptySubtitle: "Waiting for widget data", isPreview: entry.isPreview) { snapshot in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Tempo")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    Spacer()
                    if let badge = TempoWidgetFormatting.statusBadge(snapshot) {
                        TempoIOSStatusBadge(text: badge)
                    }
                }

                TempoIOSCompactMetric(
                    label: "Session",
                    value: TempoWidgetFormatting.percentString(snapshot.utilization5h),
                    progress: snapshot.utilization5h,
                    color: ClaudeCodeTheme.accent,
                    subtitle: TempoWidgetFormatting.sessionResetString(snapshot)
                )

                TempoIOSCompactMetric(
                    label: "Weekly",
                    value: TempoWidgetFormatting.percentString(snapshot.utilization7d),
                    progress: snapshot.utilization7d,
                    color: ClaudeCodeTheme.info,
                    subtitle: TempoWidgetFormatting.weeklyResetString(snapshot)
                )

                Spacer(minLength: 0)

                if snapshot.hasExtraUsageSummary {
                    Text("\(ExtraUsage.formatUSD(snapshot.extraUsageUsedAmountUSD ?? 0)) / \(ExtraUsage.formatUSD(snapshot.extraUsageLimitAmountUSD ?? 0))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                } else {
                    Text("Updated \(TempoWidgetFormatting.freshnessLabel(snapshot))")
                        .font(.caption2)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                }
            }
        }
    }
}

// MARK: - Shared Subviews

private struct TempoIOSWidgetChrome<Content: View>: View {
    let snapshot: WidgetUsageSnapshot?
    let route: TempoWidgetRoute
    let emptySubtitle: String
    let isPreview: Bool
    @ViewBuilder let content: (WidgetUsageSnapshot) -> Content

    var body: some View {
        Group {
            if isPreview || snapshot == nil {
                chrome
            } else {
                chrome
                    .widgetURL(route.url)
            }
        }
    }

    private var chrome: some View {
        ZStack {
            background

            if let snapshot {
                content(snapshot)
                    .padding(14)
            } else {
                waitingView
                    .padding(14)
            }
        }
        .containerBackground(for: .widget) {
            background
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [
                ClaudeCodeTheme.background,
                ClaudeCodeTheme.card
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var waitingView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "icloud.and.arrow.down")
                .font(.title3)
                .foregroundStyle(ClaudeCodeTheme.info)
            Text("Tempo Widget")
                .font(.headline.weight(.semibold))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            Text(emptySubtitle)
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct TempoIOSStatusBadge: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(ClaudeCodeTheme.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(ClaudeCodeTheme.surface.opacity(0.95), in: Capsule())
    }
}

private struct TempoIOSMetricRow: View {
    let title: String
    let value: String
    let subtitle: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }

            TempoIOSBar(progress: progress, color: color, height: 7)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .lineLimit(1)
        }
    }
}

private struct TempoIOSCompactMetric: View {
    let label: String
    let value: String
    let progress: Double
    let color: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Spacer()
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }

            TempoIOSBar(progress: progress, color: color, height: 6)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .lineLimit(1)
        }
    }
}

private struct TempoIOSBar: View {
    let progress: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ClaudeCodeTheme.progressTrack.opacity(0.85))
                Capsule()
                    .fill(color)
                    .frame(width: max(height, geometry.size.width * max(0, min(progress, 1))))
            }
        }
        .frame(height: height)
    }
}

private struct TempoIOSDualRing: View {
    let sessionProgress: Double
    let weeklyProgress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(ClaudeCodeTheme.progressTrack, lineWidth: 10)

            Circle()
                .trim(from: 0, to: max(0, min(weeklyProgress, 1)))
                .stroke(ClaudeCodeTheme.info, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Circle()
                .stroke(ClaudeCodeTheme.progressTrack.opacity(0.9), lineWidth: 12)
                .padding(20)

            Circle()
                .trim(from: 0, to: max(0, min(sessionProgress, 1)))
                .stroke(ClaudeCodeTheme.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(20)

            VStack(spacing: 0) {
                Text(TempoWidgetFormatting.percentString(sessionProgress))
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text("session")
                    .font(.caption2)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
        }
        .padding(.horizontal, 10)
    }
}

// MARK: - Placeholder

private extension WidgetUsageSnapshot {
    static var placeholder: WidgetUsageSnapshot {
        WidgetUsageSnapshot(usage: .mock, updatedAt: .now)
    }
}
