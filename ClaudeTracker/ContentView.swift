import SwiftUI

// MARK: - ContentView

struct ContentView: View {
    let iCloudReader: iCloudUsageReader

    var body: some View {
        switch iCloudReader.syncStatus {
        case .syncing:
            syncingView
        case .stale(let since):
            staleView(since: since)
        case .waiting:
            waitingView
        }
    }

    // MARK: - Waiting (no file detected yet)

    private var waitingView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "desktopcomputer")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Connect via Mac App")
                .font(.title.bold())
            Text("Open ClaudeTracker on your Mac and sign in to start syncing Claude usage to your Apple Watch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()
            Text("Waiting for Mac to sync…")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom)
        }
    }

    // MARK: - Syncing (fresh data)

    private var syncingView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Syncing from Mac")
                .font(.title.bold())
            Text("Claude usage is being synced from your Mac to Apple Watch.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            if let receivedAt = iCloudReader.lastReceivedAt {
                Text("Updated \(receivedAt, style: .relative) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Stale (data older than 30 min)

    private func staleView(since: Date) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 64))
                .foregroundStyle(.orange)
            Text("Mac App Not Responding")
                .font(.title.bold())
            Text("Usage data hasn't been updated in a while. Make sure ClaudeTracker is running on your Mac.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Text("Last updated \(since, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(.orange)
            Spacer()
        }
    }
}
