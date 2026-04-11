import SwiftUI
import Observation

struct ContentView: View {
    @Environment(TokenStore.self) private var store

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            ZStack {
                ringLayer(for: store)

                VStack(spacing: 2) {
                    // Large center percentage — primary glanceable metric
                    Text("\(Int(store.usageState.utilization5h * 100))%")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(ringColor(utilization: store.usageState.utilization5h))

                    // Countdown — secondary context below percentage
                    Text(formatCountdown(to: store.usageState.resetAt5h))
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        .multilineTextAlignment(.center)

                    // Extra usage badge
                    if store.usageState.isUsingExtraUsage {
                        Text("Extra")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(ClaudeCodeTheme.info)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(ClaudeCodeTheme.info.opacity(0.2), in: Capsule())
                    }

                    if store.usageState.isMocked {
                        Text("⚠ mock")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(ClaudeCodeTheme.accent)
                    }
                }
            }
        }
    }

    private func ringLayer(for store: TokenStore) -> some View {
        ZStack {
            // Track rings (background)
            Circle()
                .stroke(ClaudeCodeTheme.ringTrack, lineWidth: 7)
                .padding(4)

            Circle()
                .stroke(ClaudeCodeTheme.ringTrackInner, lineWidth: 4)
                .padding(16)

            // Primary ring — 5h utilization
            Circle()
                .trim(from: 0, to: store.usageState.utilization5h)
                .stroke(
                    ringColor(utilization: store.usageState.utilization5h),
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(4)
                .animation(.easeInOut(duration: 0.4), value: store.usageState.utilization5h)

            // Secondary ring — 7d utilization
            Circle()
                .trim(from: 0, to: store.usageState.utilization7d)
                .stroke(
                    ClaudeCodeTheme.highlight,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .padding(16)
                .animation(.easeInOut(duration: 0.4), value: store.usageState.utilization7d)
        }
    }

    private func ringColor(utilization: Double) -> Color {
        switch utilization {
        case ..<0.6: return ClaudeCodeTheme.success
        case ..<0.85: return ClaudeCodeTheme.warning
        default: return ClaudeCodeTheme.error
        }
    }

    private func formatCountdown(to date: Date) -> String {
        let seconds = date.timeIntervalSinceNow
        guard seconds > 0 else { return "Fresh window" }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)hr \(minutes)min"
        } else {
            return "\(minutes)min"
        }
    }
}

#Preview {
    ContentView()
        .environment(TokenStore())
}
