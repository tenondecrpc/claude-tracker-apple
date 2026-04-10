import SwiftUI

struct TrendView: View {
    @Environment(TokenStore.self) private var store

    var body: some View {
        let days = buildDayData()
        let avg = days.map(\.utilization).reduce(0, +) / max(Double(days.count), 1)
        let peak = days.map(\.utilization).max() ?? 0

        VStack(spacing: 4) {
            // Summary stats
            HStack(spacing: 12) {
                statLabel(title: "Avg", value: avg)
                statLabel(title: "Peak", value: peak)
            }
            .padding(.horizontal, 4)

            // Bar chart
            GeometryReader { geo in
                let barAreaHeight = geo.size.height - 16 // reserve space for day labels
                ZStack(alignment: .bottom) {
                    // Average reference line
                    if avg > 0 {
                        Rectangle()
                            .fill(ClaudeCodeTheme.textTertiary.opacity(0.5))
                            .frame(height: 1)
                            .offset(y: -(barAreaHeight * avg))
                    }

                    HStack(spacing: 3) {
                        ForEach(days) { day in
                            VStack(spacing: 2) {
                                // Extra usage dot
                                Circle()
                                    .fill(day.hasExtraUsage ? ClaudeCodeTheme.info : Color.clear)
                                    .frame(width: 4, height: 4)

                                // Bar
                                VStack {
                                    Spacer(minLength: 0)
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(day.isToday
                                              ? ClaudeCodeTheme.accent
                                              : ClaudeCodeTheme.textSecondary.opacity(0.6))
                                        .frame(height: max(2, barAreaHeight * day.utilization))
                                }
                                .frame(height: barAreaHeight)

                                // Day label
                                Text(day.dayLetter)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(day.isToday
                                                     ? ClaudeCodeTheme.textPrimary
                                                     : ClaudeCodeTheme.textTertiary)
                                    .frame(height: 12)
                            }
                        }
                    }
                }
            }

            // Empty state caption
            if days.allSatisfy({ $0.utilization == 0 }) && store.usageHistory.isEmpty {
                Text("No data")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(ClaudeCodeTheme.textTertiary)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func statLabel(title: String, value: Double) -> some View {
        HStack(spacing: 2) {
            Text(title)
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(ClaudeCodeTheme.textTertiary)
            Text("\(Int(value * 100))%")
                .font(.system(.caption, design: .rounded))
                .fontWeight(.semibold)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
    }

    private func buildDayData() -> [DayBar] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Build a dict keyed by day start
        var byDay: [Date: UsageHistorySnapshot] = [:]
        for snapshot in store.usageHistory {
            let day = calendar.startOfDay(for: snapshot.date)
            // Keep the latest snapshot per day
            if byDay[day] == nil || byDay[day]!.date < snapshot.date {
                byDay[day] = snapshot
            }
        }

        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let isToday = offset == 0
            let snapshot = byDay[day]

            // Use live utilization for today if no snapshot yet
            let utilization: Double
            let hasExtra: Bool
            if isToday && snapshot == nil {
                utilization = store.usageState.utilization5h
                hasExtra = store.usageState.isUsingExtraUsage5h
            } else {
                utilization = snapshot?.utilization5h ?? 0
                hasExtra = snapshot?.isUsingExtraUsage5h ?? false
            }

            let weekday = calendar.component(.weekday, from: day)
            return DayBar(
                id: day,
                dayLetter: dayLetter(weekday: weekday),
                utilization: utilization,
                isToday: isToday,
                hasExtraUsage: hasExtra
            )
        }
    }

    private func dayLetter(weekday: Int) -> String {
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        ["S", "M", "T", "W", "T", "F", "S"][weekday - 1]
    }
}

// MARK: - DayBar

private struct DayBar: Identifiable {
    let id: Date
    let dayLetter: String
    let utilization: Double
    let isToday: Bool
    let hasExtraUsage: Bool
}

#Preview {
    TrendView()
        .environment(TokenStore())
}
