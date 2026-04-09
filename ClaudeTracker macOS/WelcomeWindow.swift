import SwiftUI

// MARK: - WelcomeWindowView

struct WelcomeWindowView: View {
    let coordinator: MacAppCoordinator
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var pastedCode = ""
    @State private var isSubmitting = false
    @State private var signInError: String?
    @State private var isRestoringSession = false

    var body: some View {
        ZStack {
            ClaudeCodeTheme.background.ignoresSafeArea()

            if coordinator.authState.isAwaitingCode {
                codeEntryView
            } else {
                welcomeView
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: coordinator.authState.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && !isRestoringSession {
                dismissWindow(id: "welcome")
            }
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 28) {
            VStack(spacing: 10) {
                Text("Welcome to Tempo for Claude")
                    .font(.largeTitle.bold())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("Track your Claude usage right from your menu bar.")
                    .font(.body)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            menuBarPreview
                .frame(maxWidth: 300)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    Task {
                        isRestoringSession = true
                        coordinator.authState.requiresExplicitSignIn = false
                        let start = Date()
                        let restored = await coordinator.client.tryRestoreSession()
                        let elapsed = Date().timeIntervalSince(start)
                        if elapsed < 2 {
                            try? await Task.sleep(nanoseconds: UInt64((2 - elapsed) * 1_000_000_000))
                        }
                        isRestoringSession = false
                        if restored {
                            coordinator.onAuthenticated()
                            dismissWindow(id: "welcome")
                        } else {
                            coordinator.client.startOAuthFlow()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isRestoringSession {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Image(systemName: "terminal.fill")
                        }
                        Text("Sign in with Claude Code")
                    }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(ClaudeCodeTheme.accent)
                .clipShape(.rect(cornerRadius: 10))
                .disabled(isRestoringSession)

            }
        }
        .padding(40)
    }

    // MARK: - Code Entry View

    private var codeEntryView: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 48))
                .foregroundStyle(ClaudeCodeTheme.accent)

            VStack(spacing: 8) {
                Text("Paste Authorization Code")
                    .font(.title2.bold())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text("After authorizing in the browser, paste the code shown on screen.")
                    .font(.body)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 8) {
                TextField("code#state", text: $pastedCode)
                    .textFieldStyle(.roundedBorder)

                Button {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        pastedCode = string
                    }
                } label: {
                    Image(systemName: "clipboard")
                        .foregroundStyle(ClaudeCodeTheme.accent)
                }
                .buttonStyle(.plain)
                .help("Paste from clipboard")
            }
            .frame(maxWidth: 400)

            if let error = signInError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.destructive)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    pastedCode = ""
                    signInError = nil
                    coordinator.authState.isAwaitingCode = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)

                Button("Submit") {
                    Task { await submitCode() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
                .background(pastedCode.isEmpty || isSubmitting ? ClaudeCodeTheme.progressTrack : ClaudeCodeTheme.accent)
                .clipShape(.rect(cornerRadius: 8))
                .disabled(pastedCode.isEmpty || isSubmitting)
            }

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Menu Bar Preview (ring gauge mockup)

    private var menuBarPreview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Tempo")
                    .font(.subheadline.bold())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Spacer()
                Circle()
                    .fill(ClaudeCodeTheme.success)
                    .frame(width: 8, height: 8)
                    .opacity(0.4)
                Image(systemName: "arrow.clockwise")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider().overlay(ClaudeCodeTheme.progressTrack)

            VStack(alignment: .leading, spacing: 10) {
                // Ring preview
                UsageRingView(
                    sessionProgress: 0.49,
                    weeklyProgress: 0.04,
                    centerLabel: "49%"
                )
                .frame(width: 100, height: 100)
                .frame(maxWidth: .infinity)

                // Pill chips
                HStack(spacing: 6) {
                    SessionPillChip(value: "49%", label: "Resets in 13 min", accentColor: ClaudeCodeTheme.accent)
                    SessionPillChip(value: "4%", label: "Resets Sun", accentColor: ClaudeCodeTheme.info)
                }
            }
            .padding(14)
        }
        .background(ClaudeCodeTheme.surface)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(ClaudeCodeTheme.progressTrack, lineWidth: 1)
        )
    }

    // MARK: - Submit

    private func submitCode() async {
        isSubmitting = true
        signInError = nil
        defer { isSubmitting = false }
        do {
            try await coordinator.client.submitOAuthCode(pastedCode)
            pastedCode = ""
            coordinator.onAuthenticated()
        } catch {
            signInError = error.localizedDescription
        }
    }
}
