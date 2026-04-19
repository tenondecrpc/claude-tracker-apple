import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct UsageEntry: TimelineEntry {
    let date: Date
    let utilization: Double
    let appearanceMode: AppearanceMode
}

// MARK: - Provider

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), utilization: 0.42, appearanceMode: .dark)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(
            UsageEntry(
                date: Date(),
                utilization: readUtilization(),
                appearanceMode: readAppearanceMode()
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(
            date: Date(),
            utilization: readUtilization(),
            appearanceMode: readAppearanceMode()
        )
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func readUtilization() -> Double {
        UserDefaults(suiteName: TempoWatchShared.appGroupIdentifier)?
            .double(forKey: TempoWatchShared.complicationUtilization5hKey) ?? 0
    }

    private func readAppearanceMode() -> AppearanceMode {
        if let rawAppearanceMode = UserDefaults(suiteName: TempoWatchShared.appGroupIdentifier)?
            .string(forKey: TempoWatchShared.appearanceModeKey),
           let appearanceMode = AppearanceMode(rawValue: rawAppearanceMode) {
            return appearanceMode
        }
        return .dark
    }
}

// MARK: - Widget View

struct UsageGaugeWidgetView: View {
    let entry: UsageEntry

    var body: some View {
        Gauge(value: entry.utilization, in: 0...1) {
            EmptyView()
        } currentValueLabel: {
            Text("\(Int(entry.utilization * 100))")
                .font(.system(.caption2, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(gaugeColor)
        }
        .gaugeStyle(.accessoryCircular)
        .tint(gaugeColor)
    }

    private var gaugeColor: Color {
        UtilizationSeverity(utilization: entry.utilization).usageColor(normal: ClaudeCodeTheme.Usage.session)
    }
}

// MARK: - Widget Configuration

@main
struct UsageGaugeWidget: Widget {
    let kind = "UsageGaugeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageGaugeWidgetView(entry: entry)
                .applyClaudeAppearance(entry.appearanceMode)
        }
        .configurationDisplayName("Claude Usage")
        .description("Shows your current Claude usage at a glance.")
        .supportedFamilies([.accessoryCircular])
    }
}
