import SwiftUI
import Observation

struct ContentView: View {
    @Environment(TokenStore.self) private var store

    var body: some View {
        @Bindable var bindableStore = store
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            ZStack {
                ringLayer(for: store)

                VStack(spacing: 2) {
                    Text(formatCountdown(to: store.usageState.resetAt5h))
                        .font(.system(.caption, design: .rounded))
                        .fontWeight(.medium)
                        .multilineTextAlignment(.center)

                    if store.usageState.isMocked {
                        Text("⚠ mock")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(ClaudeCodeTheme.accent)
                    }
                }
            }
        }
        .sheet(item: $bindableStore.pendingCompletion) { (item: SessionInfo) in
            CompletionView(session: item)
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
        guard seconds > 0 else { return "Resetting…" }
        let totalMinutes = Int(seconds / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)hr \(minutes)min left"
        } else {
            return "\(minutes)min left"
        }
    }
}

#Preview {
    ContentView()
        .environment(TokenStore())
}
