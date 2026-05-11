import SwiftUI
import Observation

struct ContentView: View {
    @Environment(TokenStore.self) private var store
    @Environment(WatchRefreshCoordinator.self) private var refreshCoordinator
    @State private var errorAlertReason: String?

    var body: some View {
        Group {
            if store.hasNoActiveAccount {
                noAccountsState
            } else {
                dashboard
            }
        }
        .alert(
            "Refresh failed",
            isPresented: Binding(
                get: { errorAlertReason != nil },
                set: { presented in
                    if !presented { errorAlertReason = nil }
                }
            ),
            presenting: errorAlertReason
        ) { _ in
            Button("Retry") {
                errorAlertReason = nil
                refreshCoordinator.requestRefresh()
            }
            Button("Dismiss", role: .cancel) {
                errorAlertReason = nil
            }
        } message: { reason in
            Text(reason)
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        VStack(spacing: 0) {
            ringLayer
            refreshFooter
                .padding(.top, 4)
        }
    }

    private var ringLayer: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { context in
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

                    // Freshness indicator
                    freshnessLabel(now: context.date)
                }
            }
        }
    }

    // MARK: - Freshness Indicator

    @ViewBuilder
    private func freshnessLabel(now: Date) -> some View {
        if let lastReceived = store.lastRelayReceivedAtForActiveAccount {
            Text(Self.relativeUpdatedLabel(from: lastReceived, now: now))
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(ClaudeCodeTheme.textTertiary)
                .padding(.top, 2)
        }
    }

    private static func relativeUpdatedLabel(from date: Date, now: Date) -> String {
        let delta = now.timeIntervalSince(date)
        if delta < 60 {
            return "Updated just now"
        }
        let formatter = relativeFormatter
        let formatted = formatter.localizedString(for: date, relativeTo: now)
        return "Updated \(formatted)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    // MARK: - Refresh Footer

    private var refreshFooter: some View {
        HStack {
            Spacer()
            refreshButton
            Spacer()
        }
    }

    private var refreshButton: some View {
        Button {
            handleRefreshTap()
        } label: {
            refreshIcon
        }
        .buttonStyle(.plain)
        .disabled(!isRefreshEnabled)
        .opacity(isRefreshEnabled ? 1.0 : 0.4)
        .accessibilityLabel("Refresh usage")
        .accessibilityValue(accessibilityValueForRefresh)
        .frame(width: 32, height: 32)
    }

    @ViewBuilder
    private var refreshIcon: some View {
        switch refreshCoordinator.state {
        case .inProgress:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ClaudeCodeTheme.accent)
                .symbolEffect(.rotate, options: .repeating)
        case .error:
            ZStack(alignment: .topTrailing) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Circle()
                    .fill(Color.red)
                    .frame(width: 7, height: 7)
                    .offset(x: 2, y: -2)
                    .accessibilityHidden(true)
            }
        case .idle:
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
        }
    }

    private var isRefreshEnabled: Bool {
        guard !store.hasNoActiveAccount else { return false }
        return store.activeAccountId != nil
    }

    private var accessibilityValueForRefresh: String {
        switch refreshCoordinator.state {
        case .idle: return "Idle"
        case .inProgress: return "Refreshing"
        case .error(let reason): return "Error: \(reason)"
        }
    }

    private func handleRefreshTap() {
        switch refreshCoordinator.state {
        case .error(let reason):
            errorAlertReason = reason
        case .idle, .inProgress:
            refreshCoordinator.requestRefresh()
        }
    }

    // MARK: - No Accounts State

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
    let store = TokenStore()
    return ContentView()
        .environment(store)
        .environment(WatchRefreshCoordinator(store: store))
}
