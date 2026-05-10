import SwiftUI
import Observation

struct ContentView: View {
    @Environment(TokenStore.self) private var store
    @State private var isShowingAccountDetail = false

    var body: some View {
        Group {
            if store.hasNoActiveAccount {
                noAccountsState
            } else {
                dashboard
            }
        }
        .sheet(isPresented: $isShowingAccountDetail) {
            accountDetailSheet
        }
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        VStack(spacing: 2) {
            accountHeader
            ringLayer
        }
    }

    /// Small header above the ring that shows a compact account label. Tapping
    /// the label opens a sheet with the full email/display name. When there
    /// is no label and no accountId to derive one from, the header collapses
    /// so the ring retains its normal layout.
    @ViewBuilder
    private var accountHeader: some View {
        let shortLabel = shortAccountLabel()
        if shortLabel.isEmpty {
            EmptyView()
        } else {
            Button {
                isShowingAccountDetail = true
            } label: {
                Text(shortLabel)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Account")
            .accessibilityValue(fullAccountLabel())
            .accessibilityHint("Shows the full account label")
        }
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
                    // Large center percentage - primary glanceable metric
                    Text("\(Int(store.usageState.utilization5h * 100))%")
                        .font(.system(.title, design: .rounded))
                        .fontWeight(.semibold)
                        .foregroundStyle(sessionColor(utilization: store.usageState.utilization5h))

                    // Metric label - clarifies which ring the % refers to
                    Text("Session")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)

                    // Countdown - secondary context below percentage
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

    // MARK: - Account Detail Sheet

    /// Sheet surface shown when the user taps the header label. Displays the
    /// full email/display name (which may otherwise be truncated in the
    /// header) and a dismiss button.
    private var accountDetailSheet: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle")
                .font(.system(size: 26))
                .foregroundStyle(ClaudeCodeTheme.accent)
                .accessibilityHidden(true)

            Text(fullAccountLabel())
                .font(.system(.caption, design: .rounded))
                .fontWeight(.medium)
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)

            Button("Done") {
                isShowingAccountDetail = false
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Dismiss account details")
        }
        .padding()
    }

    // MARK: - Label Helpers

    /// Returns the full label for the active account, preferring the
    /// iPhone-provided `accountLabel` (typically the email address or a
    /// user-set display name) and falling back to the canonical `accountId`
    /// so the sheet always has something meaningful to show when one is
    /// available.
    private func fullAccountLabel() -> String {
        if !store.accountLabel.isEmpty {
            return store.accountLabel
        }
        if let id = store.activeAccountId, !id.isEmpty {
            return id
        }
        return ""
    }

    /// Returns a short form of the account label suitable for the watch
    /// header. Prefers the local-part of an email address (everything before
    /// `@`), otherwise falls back to initials for multi-word display names
    /// or a truncated prefix for single-word labels. Returns an empty
    /// string when there is nothing to show; callers branch on that to
    /// collapse the header.
    private func shortAccountLabel() -> String {
        let source = fullAccountLabel()
        guard !source.isEmpty else { return "" }

        if source.contains("@") {
            let prefix = source.split(separator: "@", maxSplits: 1).first.map(String.init) ?? source
            return trimmedForWatchHeader(prefix)
        }

        let words = source
            .split(whereSeparator: { $0.isWhitespace })
            .filter { !$0.isEmpty }

        if words.count >= 2 {
            let initials = words
                .prefix(2)
                .compactMap { $0.first }
                .map { String($0).uppercased() }
                .joined()
            if !initials.isEmpty {
                return initials
            }
        }

        return trimmedForWatchHeader(source)
    }

    /// Caps label length so it does not overflow the watch screen. 14
    /// characters fits comfortably even on the 40mm watch with the rounded
    /// caption font used in the header; anything longer gets an ellipsis
    /// rather than letting SwiftUI truncate mid-word.
    private func trimmedForWatchHeader(_ text: String) -> String {
        let maxLength = 14
        if text.count <= maxLength {
            return text
        }
        let prefix = text.prefix(maxLength - 1)
        return "\(prefix)…"
    }

    // MARK: - Styling Helpers

    private func sessionColor(utilization: Double) -> Color {
        UsageRingStyle.sessionColor(utilization: utilization)
    }

    private func weeklyColor(utilization: Double) -> Color {
        UsageRingStyle.weeklyColor(utilization: utilization)
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

#Preview("Dashboard") {
    ContentView()
        .environment(TokenStore())
}
