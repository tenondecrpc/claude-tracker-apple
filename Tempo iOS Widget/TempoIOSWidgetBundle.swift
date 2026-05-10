import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Timeline Entry

private struct TempoIOSEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetUsageSnapshot?
    /// The accountId the user pinned via `SelectAccountIntent`. `nil` means
    /// "follow the active account". Kept on the entry so the view can
    /// reference the original pin when rendering the "account removed"
    /// indicator after a fallback.
    let configuredAccountId: String?
    /// True when the user pinned a specific account via `SelectAccountIntent`
    /// but that accountId no longer has a snapshot in the shared store, so
    /// the provider fell back to the active-account snapshot. The view
    /// renders a small warning badge when this is true (task 8.3).
    let configuredAccountRemoved: Bool
    let isPreview: Bool
}

// MARK: - Provider

/// AppIntentTimelineProvider that honors `SelectAccountIntent`. When the
/// intent's `account` is nil, the provider reads the active-account
/// snapshot via `TempoWidgetSnapshotStore.read(platform:)`. Otherwise it
/// loads the pinned per-account snapshot via
/// `TempoWidgetSnapshotStore.read(accountId:platform:)`.
///
/// Task 8.3: when a pinned account's snapshot is missing (the user removed
/// the account on the Mac, or the snapshot has not yet synced), the
/// provider transparently falls back to the active-account snapshot and
/// flags `configuredAccountRemoved = true` on the entry so the view can
/// render a small "account removed" indicator while still showing useful
/// data.
@available(iOS 17.0, *)
private struct TempoIOSProvider: AppIntentTimelineProvider {
    typealias Intent = SelectAccountIntent
    typealias Entry = TempoIOSEntry

    func placeholder(in context: Context) -> TempoIOSEntry {
        TempoIOSEntry(
            date: .now,
            snapshot: .placeholder,
            configuredAccountId: nil,
            configuredAccountRemoved: false,
            isPreview: true
        )
    }

    func snapshot(for configuration: SelectAccountIntent, in context: Context) async -> TempoIOSEntry {
        if context.isPreview {
            return TempoIOSEntry(
                date: .now,
                snapshot: .placeholder,
                configuredAccountId: configuration.account?.id,
                configuredAccountRemoved: false,
                isPreview: true
            )
        }
        let resolved = resolveSnapshot(for: configuration)
        return TempoIOSEntry(
            date: .now,
            snapshot: resolved.snapshot,
            configuredAccountId: configuration.account?.id,
            configuredAccountRemoved: resolved.configuredAccountRemoved,
            isPreview: false
        )
    }

    func timeline(for configuration: SelectAccountIntent, in context: Context) async -> Timeline<TempoIOSEntry> {
        let entry: TempoIOSEntry
        if context.isPreview {
            entry = TempoIOSEntry(
                date: .now,
                snapshot: .placeholder,
                configuredAccountId: configuration.account?.id,
                configuredAccountRemoved: false,
                isPreview: true
            )
        } else {
            let resolved = resolveSnapshot(for: configuration)
            entry = TempoIOSEntry(
                date: .now,
                snapshot: resolved.snapshot,
                configuredAccountId: configuration.account?.id,
                configuredAccountRemoved: resolved.configuredAccountRemoved,
                isPreview: false
            )
        }
        return Timeline(entries: [entry], policy: .never)
    }

    /// Resolve the snapshot for the current configuration, applying the
    /// task 8.3 fallback: if the user pinned a specific accountId but no
    /// snapshot exists for that id, read the active-account snapshot
    /// instead and flag the entry so the view can surface a non-intrusive
    /// "account removed" indicator.
    private func resolveSnapshot(
        for configuration: SelectAccountIntent
    ) -> (snapshot: WidgetUsageSnapshot?, configuredAccountRemoved: Bool) {
        guard let pinnedAccountId = configuration.account?.id, !pinnedAccountId.isEmpty else {
            return (TempoWidgetSnapshotStore.read(platform: .iOS), false)
        }
        if let pinned = TempoWidgetSnapshotStore.read(accountId: pinnedAccountId, platform: .iOS) {
            return (pinned, false)
        }
        // Pinned account vanished (signed out, removed, or snapshot not yet
        // synced). Render the active account's data below a warning badge.
        return (TempoWidgetSnapshotStore.read(platform: .iOS), true)
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
        AppIntentConfiguration(
            kind: TempoWidgetKind.iOSRing,
            intent: SelectAccountIntent.self,
            provider: TempoIOSProvider()
        ) { entry in
            TempoIOSRingWidgetView(entry: entry)
                .applyClaudeAppearance(entry.snapshot?.appearanceMode ?? .dark)
        }
        .configurationDisplayName("Tempo Usage")
        .description("Current Claude usage with a dual ring.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

private struct TempoIOSSummaryWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: TempoWidgetKind.iOSSummary,
            intent: SelectAccountIntent.self,
            provider: TempoIOSProvider()
        ) { entry in
            TempoIOSSummaryWidgetView(entry: entry)
                .applyClaudeAppearance(entry.snapshot?.appearanceMode ?? .dark)
        }
        .configurationDisplayName("Tempo Summary")
        .description("Current session and weekly usage in a wide summary.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}

private struct TempoIOSCompactWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: TempoWidgetKind.iOSCompact,
            intent: SelectAccountIntent.self,
            provider: TempoIOSProvider()
        ) { entry in
            TempoIOSCompactWidgetView(entry: entry)
                .applyClaudeAppearance(entry.snapshot?.appearanceMode ?? .dark)
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
        TempoIOSWidgetChrome(
            snapshot: entry.snapshot,
            routeKind: .dashboard,
            emptySubtitle: "Open Tempo on your iPhone",
            isPreview: entry.isPreview,
            configuredAccountRemoved: entry.configuredAccountRemoved
        ) { snapshot in
            TempoIOSDualRing(
                sessionProgress: snapshot.utilization5h,
                weeklyProgress: snapshot.utilization7d
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct TempoIOSSummaryWidgetView: View {
    let entry: TempoIOSEntry

    var body: some View {
        TempoIOSWidgetChrome(
            snapshot: entry.snapshot,
            routeKind: .dashboard,
            emptySubtitle: "Open Tempo to start syncing from your Mac",
            isPreview: entry.isPreview,
            configuredAccountRemoved: entry.configuredAccountRemoved
        ) { snapshot in
            ViewThatFits(in: .vertical) {
                summaryContent(snapshot: snapshot, isCompact: false)
                summaryContent(snapshot: snapshot, isCompact: true)
            }
        }
    }

    @ViewBuilder
    private func summaryContent(snapshot: WidgetUsageSnapshot, isCompact: Bool) -> some View {
        let sessionColor = UtilizationSeverity(utilization: snapshot.utilization5h).usageColor(normal: ClaudeCodeTheme.Usage.session)
        let weeklyColor = UtilizationSeverity(utilization: snapshot.utilization7d).usageColor(normal: ClaudeCodeTheme.Usage.weekly)

        VStack(alignment: .leading, spacing: isCompact ? 8 : 10) {
            TempoIOSMetricRow(
                title: "Current Session",
                value: TempoWidgetFormatting.percentString(snapshot.utilization5h),
                subtitle: TempoWidgetFormatting.sessionResetString(snapshot),
                progress: snapshot.utilization5h,
                color: sessionColor,
                valueFontSize: isCompact ? 10 : 11,
                barHeight: isCompact ? 7 : 8,
                verticalSpacing: isCompact ? 2 : 3
            )

            TempoIOSMetricRow(
                title: "Weekly Limit",
                value: TempoWidgetFormatting.percentString(snapshot.utilization7d),
                subtitle: TempoWidgetFormatting.weeklyResetString(snapshot),
                progress: snapshot.utilization7d,
                color: weeklyColor,
                valueFontSize: isCompact ? 10 : 11,
                barHeight: isCompact ? 7 : 8,
                verticalSpacing: isCompact ? 2 : 3
            )

            if snapshot.hasExtraUsageSummary {
                TempoIOSExtraUsageRow(snapshot: snapshot, isCompact: isCompact)
            }

            TempoIOSFreshnessFooter(snapshot: snapshot)
        }
    }
}

private struct TempoIOSCompactWidgetView: View {
    let entry: TempoIOSEntry

    var body: some View {
        TempoIOSWidgetChrome(
            snapshot: entry.snapshot,
            routeKind: .dashboard,
            emptySubtitle: "Waiting for widget data",
            isPreview: entry.isPreview,
            configuredAccountRemoved: entry.configuredAccountRemoved
        ) { snapshot in
            let sessionColor = UtilizationSeverity(utilization: snapshot.utilization5h).usageColor(normal: ClaudeCodeTheme.Usage.session)
            let weeklyColor = UtilizationSeverity(utilization: snapshot.utilization7d).usageColor(normal: ClaudeCodeTheme.Usage.weekly)

            VStack(alignment: .leading, spacing: 0) {
                TempoIOSSuperscriptMetric(
                    value: TempoWidgetFormatting.percentValue(snapshot.utilization5h),
                    label: "Current",
                    subtitle: TempoWidgetFormatting.sessionResetString(snapshot, compact: true),
                    color: sessionColor
                )

                Spacer(minLength: 0)

                TempoIOSSuperscriptMetric(
                    value: TempoWidgetFormatting.percentValue(snapshot.utilization7d),
                    label: "Weekly",
                    subtitle: TempoWidgetFormatting.weeklyResetString(snapshot),
                    color: weeklyColor
                )
            }
        }
    }
}

// MARK: - Shared Subviews

private struct TempoIOSWidgetChrome<Content: View>: View {
    let snapshot: WidgetUsageSnapshot?
    let routeKind: TempoWidgetRoute.Kind
    let emptySubtitle: String
    let isPreview: Bool
    /// When true, overlay a small "Account removed" badge in the top-right
    /// corner of the widget chrome. Set by the provider when the pinned
    /// accountId from `SelectAccountIntent` has no snapshot and the
    /// provider fell back to the active-account snapshot (task 8.3).
    let configuredAccountRemoved: Bool
    @ViewBuilder let content: (WidgetUsageSnapshot) -> Content

    var body: some View {
        Group {
            if isPreview || snapshot == nil {
                chrome
            } else {
                // Embed the rendered snapshot's accountId in the tap URL
                // so the iOS app switches to that account before showing
                // the dashboard. When the snapshot belongs to the
                // currently active account the query item is redundant
                // but harmless; when the widget is pinned to a specific
                // account via `SelectAccountIntent` it ensures the app
                // lands on that same account (task 8.4).
                chrome
                    .widgetURL(
                        TempoWidgetRoute(
                            kind: routeKind,
                            accountId: snapshot?.accountId
                        ).url
                    )
            }
        }
    }

    private var chrome: some View {
        ZStack(alignment: .topTrailing) {
            background

            if let snapshot {
                content(snapshot)
                    .padding(14)
            } else {
                waitingView
                    .padding(14)
            }

            if configuredAccountRemoved {
                TempoIOSAccountRemovedBadge()
                    .padding(.top, 6)
                    .padding(.trailing, 6)
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
        ViewThatFits(in: .vertical) {
            richWaitingView
            compactWaitingView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var richWaitingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Tempo Widget", systemImage: "icloud.and.arrow.down")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    Text("Waiting for Mac sync")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                }
                Spacer()
                TempoIOSStatusBadge(text: "sync")
            }

            placeholderMetric(label: "Current Session")
            placeholderMetric(label: "Weekly Limit")

            Text(emptySubtitle)
                .font(.caption2)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
        }
    }

    private var compactWaitingView: some View {
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
                .lineLimit(3)
                .minimumScaleFactor(0.85)
            Spacer(minLength: 0)
        }
    }

    private func placeholderMetric(label: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Spacer()
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ClaudeCodeTheme.textTertiary.opacity(0.28))
                    .frame(width: 34, height: 12)
            }

            RoundedRectangle(cornerRadius: 999, style: .continuous)
                .fill(ClaudeCodeTheme.progressTrack.opacity(0.7))
                .frame(height: 7)
        }
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

/// Small non-intrusive badge shown in the top-right of the widget chrome
/// when the pinned account has been removed and the provider fell back to
/// the active account (task 8.3). Keeps the underlying widget data visible
/// so the user still sees something useful.
private struct TempoIOSAccountRemovedBadge: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(ClaudeCodeTheme.warning)
            Text("Account removed")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(ClaudeCodeTheme.surface.opacity(0.95), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pinned account removed, showing active account")
    }
}

private struct TempoIOSMetricRow: View {
    let title: String
    let value: String
    let subtitle: String
    let progress: Double
    let color: Color
    let valueFontSize: CGFloat
    let barHeight: CGFloat
    let verticalSpacing: CGFloat

    init(
        title: String,
        value: String,
        subtitle: String,
        progress: Double,
        color: Color,
        valueFontSize: CGFloat = 16,
        barHeight: CGFloat = 7,
        verticalSpacing: CGFloat = 4
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.progress = progress
        self.color = color
        self.valueFontSize = valueFontSize
        self.barHeight = barHeight
        self.verticalSpacing = verticalSpacing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: verticalSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Spacer()
                Text(value)
                    .font(.system(size: valueFontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
            }

            TempoIOSBar(progress: progress, color: color, height: barHeight)

            Text(subtitle)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

private struct TempoIOSExtraUsageRow: View {
    let snapshot: WidgetUsageSnapshot
    let isCompact: Bool

    private var extraUsageProgress: Double {
        let rawValue = snapshot.extraUsageUtilizationPercent ?? 0
        return rawValue > 1 ? rawValue / 100.0 : rawValue
    }

    private var extraColor: Color {
        UtilizationSeverity(utilization: extraUsageProgress).usageColor(normal: ClaudeCodeTheme.Usage.normal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Extra Usage")
                    .font((isCompact ? Font.system(size: 10) : .caption).weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                Spacer(minLength: 6)
                Text(TempoWidgetFormatting.extraUsageSummaryString(snapshot, compact: false) ?? "")
                    .font((isCompact ? Font.system(size: 10) : .caption).monospacedDigit())
                    .foregroundStyle(extraColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            TempoIOSBar(
                progress: extraUsageProgress,
                color: extraColor,
                height: isCompact ? 7 : 8
            )
        }
    }
}

private struct TempoIOSFreshnessFooter: View {
    let snapshot: WidgetUsageSnapshot

    var body: some View {
        HStack(spacing: 4) {
            Spacer()
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            Text(TempoWidgetFormatting.freshnessLabel(snapshot))
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

private struct TempoIOSSuperscriptMetric: View {
    let value: Int
    let label: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(value)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Text("%")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(color)
                Spacer(minLength: 0)
            }

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
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
        TempoUsageRing(
            sessionProgress: sessionProgress,
            weeklyProgress: weeklyProgress
        ) {
            VStack(spacing: 1) {
                Text(TempoWidgetFormatting.percentString(sessionProgress))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(UsageRingStyle.sessionColor(utilization: sessionProgress))
                Text("5H")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Placeholder

private extension WidgetUsageSnapshot {
    static var placeholder: WidgetUsageSnapshot {
        WidgetUsageSnapshot(
            usage: .mock,
            updatedAt: .now,
            accountLabel: "preview@example.com"
        )
    }
}
