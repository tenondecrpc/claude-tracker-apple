import SwiftUI

struct SettingsTabView: View {
    @Bindable var store: IOSAppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                preferencesCard
                diagnosticsCard
                helpCard
            }
            .padding(16)
        }
        .background(ClaudeCodeTheme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Settings")
                .font(.title2.weight(.semibold))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            Text("Local display preferences and iCloud sync diagnostics")
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
    }

    private var preferencesCard: some View {
        card(title: "Display") {
            Toggle("Use 24-hour time", isOn: $store.use24HourTime)
                .tint(ClaudeCodeTheme.accent)
            Divider().overlay(ClaudeCodeTheme.progressTrack)
            Toggle("Show 5-hour series in Activity", isOn: $store.showSessionSeries)
                .tint(ClaudeCodeTheme.accent)
            Divider().overlay(ClaudeCodeTheme.progressTrack)
            Toggle("Show 7-day series in Activity", isOn: $store.showWeeklySeries)
                .tint(ClaudeCodeTheme.info)
        }
    }

    private var diagnosticsCard: some View {
        card(title: "Data & Sync") {
            VStack(alignment: .leading, spacing: 10) {
                diagnosticLine(
                    title: "Usage file",
                    status: store.usageSyncStatus,
                    lastUpdate: store.lastUsageUpdate
                )
                diagnosticLine(
                    title: "History file",
                    status: store.historySyncStatus,
                    lastUpdate: store.lastHistoryUpdate
                )

                if let usageReadError = store.usageReadError {
                    Text("Usage read error: \(usageReadError)")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.error)
                }
                if let historyReadError = store.historyReadError {
                    Text("History read error: \(historyReadError)")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.error)
                }

                Button {
                    store.iCloudReader.restart()
                } label: {
                    Label("Rescan iCloud files", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.accent)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private var helpCard: some View {
        card(title: "Connection") {
            Text("iOS reads usage from iCloud only. Authentication and polling happen on your Mac app.")
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
            Divider().overlay(ClaudeCodeTheme.progressTrack)
            Text("Keep Tempo open on Mac to receive frequent updates on iPhone and Apple Watch.")
                .font(.subheadline)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
    }

    private func diagnosticLine(
        title: String,
        status: iCloudUsageReader.SyncStatus,
        lastUpdate: Date?
    ) -> some View {
        let color: Color
        let statusText: String

        switch status {
        case .waiting:
            color = ClaudeCodeTheme.info
            statusText = "Waiting for file"
        case .syncing:
            color = ClaudeCodeTheme.success
            if let lastUpdate {
                statusText = "Updated \(relativeAgeText(lastUpdate))"
            } else {
                statusText = "Synced"
            }
        case .stale(let since):
            color = ClaudeCodeTheme.warning
            statusText = "Stale since \(relativeAgeText(since))"
        }

        return HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            Spacer()
            Text(statusText)
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
        }
    }

    @ViewBuilder
    private func card<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ClaudeCodeTheme.card)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(ClaudeCodeTheme.border.opacity(0.6), lineWidth: 1)
        )
    }

    private func relativeAgeText(_ date: Date) -> String {
        RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
