import Foundation

// MARK: - TempoWidgetFormatting

enum TempoWidgetFormatting {
    private static let widgetCurrencyFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.currencySymbol = "$"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func percentValue(_ utilization: Double) -> Int {
        Int(UsageHistoryTransformer.boundedPercent(utilization).rounded())
    }

    static func percentString(_ utilization: Double) -> String {
        "\(percentValue(utilization))%"
    }

    static func sessionResetString(
        _ snapshot: WidgetUsageSnapshot,
        now: Date = Date(),
        use24HourTime: Bool = false,
        compact: Bool = false
    ) -> String {
        TimeFormatPolicy.sessionResetString(
            resetAt: snapshot.resetAt5h,
            now: now,
            use24HourTime: use24HourTime,
            compact: compact
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
        let seconds = Int(now.timeIntervalSince(snapshot.updatedAt))
        if seconds < 60 {
            return "just now"
        }
        return RelativeDateTimeFormatter().localizedString(for: snapshot.updatedAt, relativeTo: now)
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

    static func widgetCurrencyString(_ amount: Double) -> String {
        widgetCurrencyFormatter.string(from: NSNumber(value: amount))
            ?? String(format: "$%.2f", amount)
    }

    static func extraUsageSummaryString(
        _ snapshot: WidgetUsageSnapshot,
        compact: Bool = false
    ) -> String? {
        guard snapshot.hasExtraUsageSummary else { return nil }

        let used = widgetCurrencyString(snapshot.extraUsageUsedAmountUSD ?? 0)
        let limit = widgetCurrencyString(snapshot.extraUsageLimitAmountUSD ?? 0)
        return compact ? "\(used)/\(limit)" : "\(used) / \(limit)"
    }
}
