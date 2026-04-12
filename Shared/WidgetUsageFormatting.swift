import Foundation

// MARK: - TempoWidgetFormatting

enum TempoWidgetFormatting {
    static func percentString(_ utilization: Double) -> String {
        "\(Int(UsageHistoryTransformer.boundedPercent(utilization).rounded()))%"
    }

    static func sessionResetString(
        _ snapshot: WidgetUsageSnapshot,
        now: Date = Date(),
        use24HourTime: Bool = false
    ) -> String {
        TimeFormatPolicy.sessionResetString(
            resetAt: snapshot.resetAt5h,
            now: now,
            use24HourTime: use24HourTime
        )
    }

    static func weeklyResetString(
        _ snapshot: WidgetUsageSnapshot,
        use24HourTime: Bool = false
    ) -> String {
        TimeFormatPolicy.weeklyResetString(
            resetAt: snapshot.resetAt7d,
            use24HourTime: use24HourTime
        )
    }

    static func freshnessLabel(_ snapshot: WidgetUsageSnapshot, now: Date = Date()) -> String {
        switch WidgetFreshnessPolicy.status(updatedAt: snapshot.updatedAt, now: now) {
        case .fresh:
            return "now"
        case .stale(let since):
            return RelativeDateTimeFormatter().localizedString(for: since, relativeTo: now)
        }
    }

    static func statusBadge(_ snapshot: WidgetUsageSnapshot, now: Date = Date()) -> String? {
        if snapshot.isMocked {
            return "mock"
        }

        switch WidgetFreshnessPolicy.status(updatedAt: snapshot.updatedAt, now: now) {
        case .fresh:
            return nil
        case .stale:
            return "stale"
        }
    }
}
