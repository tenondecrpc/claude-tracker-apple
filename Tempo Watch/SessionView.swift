import SwiftUI

struct SessionView: View {
    @Environment(TokenStore.self) private var store
    @State private var pulsing = false

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 60)) { _ in
            if let session = store.lastSession {
                sessionCard(session)
            } else {
                emptyState
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Session Card

    private func sessionCard(_ session: SessionInfo) -> some View {
        VStack(spacing: 6) {
            // Card background
            VStack(spacing: 4) {
                // Primary: total tokens
                Text(formatTokens(session.inputTokens + session.outputTokens))
                    .font(.system(.title3, design: .rounded))
                    .fontWeight(.semibold)
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)

                // Secondary: cost + duration
                HStack(spacing: 8) {
                    Text(formatCost(session.costUSD))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    Text("·")
                        .foregroundStyle(ClaudeCodeTheme.textTertiary)
                    Text(formatDuration(session.durationSeconds))
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                }

                // Timestamp
                Text(relativeTime(from: session.timestamp))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(ClaudeCodeTheme.textTertiary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .background(ClaudeCodeTheme.card, in: RoundedRectangle(cornerRadius: 12))

            // Status row
            HStack(spacing: 8) {
                activityIndicator(for: session.timestamp)
                Spacer()
                Image(systemName: store.areNotificationsEnabled ? "bell.fill" : "bell.slash")
                    .font(.system(size: 11))
                    .foregroundStyle(
                        store.areNotificationsEnabled
                        ? ClaudeCodeTheme.accent
                        : ClaudeCodeTheme.textTertiary
                    )
                    .accessibilityLabel(
                        store.areNotificationsEnabled
                        ? "Notifications enabled"
                        : "Notifications disabled"
                    )
            }
        }
    }

    // MARK: - Activity Indicator

    private func activityIndicator(for timestamp: Date) -> some View {
        let isActive = Date().timeIntervalSince(timestamp) < 5 * 60

        return HStack(spacing: 4) {
            Circle()
                .fill(isActive ? ClaudeCodeTheme.success : ClaudeCodeTheme.textTertiary)
                .frame(width: 6, height: 6)
                .scaleEffect(isActive && pulsing ? 1.3 : 1.0)
                .animation(
                    isActive
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                    value: pulsing
                )
                .onAppear { pulsing = true }

            Text(isActive ? "Active" : "Idle")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(isActive ? ClaudeCodeTheme.success : ClaudeCodeTheme.textTertiary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 22))
                .foregroundStyle(ClaudeCodeTheme.textTertiary)
            Text("No sessions yet")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(ClaudeCodeTheme.textTertiary)

            HStack(spacing: 4) {
                Circle()
                    .fill(ClaudeCodeTheme.textTertiary)
                    .frame(width: 6, height: 6)
                Text("Idle")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(ClaudeCodeTheme.textTertiary)
            }
        }
    }

    // MARK: - Formatters

    private func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            let k = Double(count) / 1000.0
            return String(format: "%.1fK tokens", k)
        }
        return "\(count) tokens"
    }

    private func formatCost(_ usd: Double) -> String {
        String(format: "$%.2f", usd)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        if m > 0 {
            return "\(m)m \(s)s"
        }
        return "\(s)s"
    }

    private func relativeTime(from date: Date) -> String {
        let elapsed = Int(Date().timeIntervalSince(date))
        if elapsed < 60 { return "just now" }
        let minutes = elapsed / 60
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) hr ago" }
        return "\(hours / 24) d ago"
    }
}

#Preview {
    SessionView()
        .environment(TokenStore())
}
