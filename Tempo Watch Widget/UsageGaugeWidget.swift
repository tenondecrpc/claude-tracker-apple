import WidgetKit
import SwiftUI

// MARK: - App Group ID

private let appGroupID = "group.com.tenondecrpc.tempo.watch"
private let utilizationKey = "complication_utilization5h"

// MARK: - Timeline Entry

struct UsageEntry: TimelineEntry {
    let date: Date
    let utilization: Double
}

// MARK: - Provider

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), utilization: 0.42)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(UsageEntry(date: Date(), utilization: readUtilization()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let entry = UsageEntry(date: Date(), utilization: readUtilization())
        completion(Timeline(entries: [entry], policy: .never))
    }

    private func readUtilization() -> Double {
        UserDefaults(suiteName: appGroupID)?.double(forKey: utilizationKey) ?? 0
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
        switch entry.utilization {
        case ..<0.6:  return Color(red: 0.604, green: 0.792, blue: 0.525) // ClaudeCodeTheme.success dark
        case ..<0.85: return Color(red: 0.910, green: 0.788, blue: 0.420) // ClaudeCodeTheme.warning dark
        default:      return Color(red: 0.831, green: 0.459, blue: 0.388) // ClaudeCodeTheme.error dark
        }
    }
}

// MARK: - Widget Configuration

@main
struct UsageGaugeWidget: Widget {
    let kind = "UsageGaugeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            UsageGaugeWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Shows your current Claude usage at a glance.")
        .supportedFamilies([.accessoryCircular])
    }
}
