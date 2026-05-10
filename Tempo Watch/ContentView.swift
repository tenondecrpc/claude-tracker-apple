import SwiftUI
import Observation

struct ContentView: View {
    @Environment(TokenStore.self) private var store

    var body: some View {
        Group {
            if store.hasNoActiveAccount {
                noAccountsState
            } else {
                dashboard
            }
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        ringLayer
    }

    private var ringLayer: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            ZStack {
                TempoUsageRing(
                    sessionProgress: store.usageState.utilization5h,
                    weeklyProgress: store.usageState.utilization7d
                )
                .padding(4)
                .animation(.easeInOut(duration: 0.4), value: store.usageState.utilization5h)
                .animation(.easeInOut(duration: 0.4), value: store.usageState.utilization7d)

                VStack(spacing: 2) {
                    // Large center percentage - primary 5H session metric
                    Text("\(Int(store.usageState.utilization5h * 100))%")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(sessionColor(utilization: store.usageState.utilization5h))

                    // Metric label - clarifies which ring the % refers to
                    Text("5H")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)

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

    // MARK: - No Accounts State

    /// Rendered in place of the ring when the iPhone has relayed
    /// `NoActiveAccount`. Matches design.md "Watch UX": a simple glyph plus
    /// instructional text pointing the user back to the Mac app, since the
    /// watch cannot add or pick accounts on its own.
    private var noAccountsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 28))
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .accessibilityHidden(true)

            Text("No accounts available")
                .font(.system(.caption, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .multilineTextAlignment(.center)

            Text("Check the Mac app to add one")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(ClaudeCodeTheme.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
        }
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No accounts available. Check the Mac app to add one.")
    }

    // MARK: - Styling Helpers

    private func sessionColor(utilization: Double) -> Color {
        UsageRingStyle.sessionColor(utilization: utilization)
    }
}

#Preview("Dashboard") {
    ContentView()
        .environment(TokenStore())
}
