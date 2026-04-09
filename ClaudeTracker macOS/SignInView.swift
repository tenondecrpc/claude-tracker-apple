import SwiftUI

// MARK: - MacMenuView (top-level switcher)

struct MacMenuView: View {
    let coordinator: MacAppCoordinator

    var body: some View {
        if coordinator.authState.isAuthenticated {
            DashboardPopoverView(coordinator: coordinator)
        } else {
            NotSignedInMenuView(coordinator: coordinator)
        }
    }
}

// MARK: - NotSignedInMenuView

struct NotSignedInMenuView: View {
    let coordinator: MacAppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            MenuBarHeaderView()

            VStack(spacing: 16) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(ClaudeCodeTheme.info)
                    .padding(.top, 24)

                VStack(spacing: 6) {
                    Text("Not Signed In")
                        .font(.headline)
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    Text("Sign in to view your usage")
                        .font(.caption)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)

                Button {
                    NSApp.keyWindow?.close()
                    openWindow(id: "welcome")
                } label: {
                    Text("Sign In")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(ClaudeCodeTheme.accent)
                .clipShape(.rect(cornerRadius: 10))
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()
                .overlay(ClaudeCodeTheme.progressTrack)

            HStack {
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ClaudeCodeTheme.error)
                .font(.caption)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(ClaudeCodeTheme.background)
        .preferredColorScheme(.dark)
    }
}
