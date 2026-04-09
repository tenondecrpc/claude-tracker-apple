import SwiftUI
import AppKit

// MARK: - MacMenuView (top-level switcher)

struct MacMenuView: View {
    let coordinator: MacAppCoordinator

    var body: some View {
        Group {
            if coordinator.authState.isAuthenticated {
                DashboardPopoverView(coordinator: coordinator)
            } else {
                NotSignedInMenuView(coordinator: coordinator)
            }
        }
        .onAppear {
            scheduleMenuWindowRecenter()
        }
        .onChange(of: coordinator.authState.isAuthenticated) { _, _ in
            scheduleMenuWindowRecenter()
        }
        .onChange(of: coordinator.poller.latestUsage != nil) { _, _ in
            scheduleMenuWindowRecenter()
        }
    }

    private func scheduleMenuWindowRecenter() {
        DispatchQueue.main.async {
            centerMenuWindowUnderMenuBarClick()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            centerMenuWindowUnderMenuBarClick()
        }
    }

    private func centerMenuWindowUnderMenuBarClick() {
        guard let menuWindow = NSApp.keyWindow else { return }

        let clickLocation = NSEvent.mouseLocation
        var frame = menuWindow.frame
        let visibleFrame = menuWindow.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        guard !visibleFrame.isEmpty else { return }

        let desiredX = clickLocation.x - (frame.width / 2)
        let horizontalInset: CGFloat = 8
        let minX = visibleFrame.minX + horizontalInset
        let maxX = visibleFrame.maxX - frame.width - horizontalInset

        frame.origin.x = min(max(desiredX, minX), maxX)
        menuWindow.setFrameOrigin(frame.origin)
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
