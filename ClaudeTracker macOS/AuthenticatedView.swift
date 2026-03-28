import SwiftUI

// MARK: - AuthenticatedView

struct AuthenticatedView: View {
    let coordinator: MacAppCoordinator

    var body: some View {
        VStack(spacing: 12) {
            // Status header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Connected")
                    .font(.headline)
                Spacer()
            }

            // Account email from ~/.claude/.claude.json
            if let email = coordinator.authState.accountEmail {
                HStack {
                    Text(email)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            Divider()

            // Last poll timestamp
            HStack {
                Text("Last synced")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastPollAt = coordinator.poller.lastPollAt {
                    Text(lastPollAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Polling…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button("Sign Out", role: .destructive) {
                coordinator.client.signOut()
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }
}
