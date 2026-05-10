import SwiftUI

// MARK: - WelcomeWindowView

struct WelcomeWindowView: View {
    let coordinator: MacAppCoordinator
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var pastedCode = ""
    @State private var isSubmitting = false
    @State private var signInError: String?
    @State private var isRestoringSession = false
    @State private var cliRestoreError: String?

    private var isSubmitDisabled: Bool {
        pastedCode.isEmpty || isSubmitting
    }

    /// True when an authenticated user opens the window from the menu
    /// bar's "Switch account" affordance. A stale registry row while signed
    /// out must not switch the unauthenticated Sign In flow to account-switch
    /// copy. While a CLI restore is in progress, keep the first-sign-in
    /// layout stable because the restore registers an account just before
    /// this window dismisses.
    private var isAddingAccount: Bool {
        coordinator.authState.isAuthenticated
            && !isRestoringSession
            && !coordinator.registry.accounts.isEmpty
    }

    var body: some View {
        ZStack {
            ClaudeCodeTheme.background.ignoresSafeArea()

            if coordinator.authState.isAwaitingCode {
                codeEntryView
            } else {
                welcomeView
            }
        }
        .onChange(of: coordinator.authState.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated && !isRestoringSession {
                dismissWindow(id: "welcome")
            }
        }
    }

    // MARK: - Welcome View

    private var welcomeView: some View {
        VStack(spacing: 22) {
            // Account-switch mode reuses this window but the content is
            // much shorter. Without a top spacer the hero would stick to
            // the title bar and leave a huge gap above the CTA. Mirroring
            // the spacer at the bottom centres the smaller layout.
            if isAddingAccount { Spacer(minLength: 0) }

            heroHeader

            // The menu-bar preview is a first-run affordance. Returning
            // users opening the window via "Switch account" already know the
            // product, so skip the preview to keep the focus on sign-in.
            if !isAddingAccount {
                menuBarPreview
                    .frame(maxWidth: 280)
            }

            // Compact value-prop strip replacing the long Authentication
            // paragraph. Keychain reassurance is now one of three icon
            // chips so the copy never overflows the window width.
            if !isAddingAccount {
                featureHighlights
                Spacer(minLength: 4)
            }

            VStack(spacing: 12) {
                primaryCTA

                Text(isAddingAccount
                     ? "Anthropic OAuth verifies the email so this account stays isolated from the current one."
                     : "Recommended. Verified via Anthropic so account data stays cleanly isolated.")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                // CLI fallback only makes sense on first sign-in. In
                // account-switch mode the user is explicitly trying to use
                // a different account, so re-restoring the existing CLI
                // session would defeat the purpose.
                if !isAddingAccount {
                    cliFallbackSection
                }

                if isAddingAccount {
                    Button("Cancel") {
                        dismissWindow(id: "welcome")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .padding(.top, 4)
                }
            }

            if isAddingAccount { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 32)
        .frame(maxWidth: 580)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Hero header

    private var heroHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ClaudeCodeTheme.accentMuted)
                    .frame(width: 56, height: 56)
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(ClaudeCodeTheme.accent)
            }
            .padding(.bottom, 4)

            Text(isAddingAccount ? "Switch account" : "Welcome to Tempo for Claude")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .multilineTextAlignment(.center)
            Text(isAddingAccount
                 ? "Sign in with a different Anthropic account. Tempo keeps each account's data isolated."
                 : "Track your Claude usage from the menu bar - sessions, weekly limits, and resets at a glance.")
                .font(.body)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Feature highlights

    private var featureHighlights: some View {
        HStack(spacing: 10) {
            FeatureChip(
                icon: "lock.shield.fill",
                title: "Secure",
                subtitle: "Tokens stored in macOS Keychain"
            )
            FeatureChip(
                icon: "person.2.fill",
                title: "Account switching",
                subtitle: "Keep each account isolated"
            )
            FeatureChip(
                icon: "menubar.dock.rectangle",
                title: "At a glance",
                subtitle: "Live usage in the menu bar"
            )
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Primary CTA

    private var primaryCTA: some View {
        // Background and shadow live on a dedicated `RoundedRectangle`
        // inside `.background`. Applying `.shadow` to the whole button
        // (after `.clipShape`) triggered a SwiftUI rendering bug on macOS
        // that flipped the label content upside-down because the label
        // got promoted to an offscreen, mirrored layer.
        Button {
            Task { await beginOAuthSignIn() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 16, weight: .semibold))
                Text(isAddingAccount
                     ? "Sign in with a different Anthropic account"
                     : "Sign in with Anthropic")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [ClaudeCodeTheme.accent, ClaudeCodeTheme.accentLight],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .shadow(color: ClaudeCodeTheme.accent.opacity(0.28), radius: 10, y: 4)
        )
        .disabled(isRestoringSession)
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

                Button {
                    Task { await submitCode() }
                } label: {
                    Text("Submit")
                        .foregroundStyle(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(isSubmitDisabled ? ClaudeCodeTheme.progressTrack : ClaudeCodeTheme.accent)
                        .clipShape(.rect(cornerRadius: 8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isSubmitDisabled)
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
                    centerLabel: "4%"
                )
                .frame(width: 100, height: 100)
                .frame(maxWidth: .infinity)

                // Pill chips
                HStack(spacing: 6) {
                    SessionPillChip(value: "49%", label: "Resets in 13 min", accentColor: ClaudeCodeTheme.Usage.session)
                    SessionPillChip(value: "4%", label: "Resets Sun", accentColor: ClaudeCodeTheme.Usage.weekly)
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

    // MARK: - CLI fallback section
    //
    // Secondary, less-prominent affordance for users who want to reuse the
    // existing Claude Code CLI session. Includes an explicit warning that
    // CLI-restored sessions cannot be reliably mapped to a specific
    // Anthropic account (see docs/AUTH_FLOW.md): the CLI does not surface
    // the email under App Sandbox, so multiple-account tracking is not
    // available via this path.
    private var cliFallbackSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Rectangle()
                    .fill(ClaudeCodeTheme.progressTrack)
                    .frame(height: 1)
                Text("OR")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.4)
                    .foregroundStyle(ClaudeCodeTheme.textTertiary)
                Rectangle()
                    .fill(ClaudeCodeTheme.progressTrack)
                    .frame(height: 1)
            }
            .padding(.vertical, 2)

            Button {
                Task { await beginCLISignIn() }
            } label: {
                HStack(spacing: 8) {
                    if isRestoringSession {
                        ProgressView()
                            .controlSize(.small)
                            .tint(ClaudeCodeTheme.textPrimary)
                    } else {
                        Image(systemName: "terminal")
                            .font(.system(size: 14, weight: .medium))
                    }
                    Text("Use existing Claude Code CLI session")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(ClaudeCodeTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(ClaudeCodeTheme.progressTrack, lineWidth: 1)
            )
            .clipShape(.rect(cornerRadius: 10))
            .disabled(isRestoringSession)

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(ClaudeCodeTheme.warning)
                    .padding(.top, 2)
                Text("Single-account only. The CLI does not expose which Anthropic account is active.")
                    .font(.caption2)
                    .foregroundStyle(ClaudeCodeTheme.textTertiary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)

            if let cliRestoreError {
                Text(cliRestoreError)
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.destructive)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Sign-in entry points
    //
    // OAuth is the recommended path: after the code exchange the app
    // calls `https://api.anthropic.com/api/oauth/profile` with the
    // freshly-issued access token to retrieve the verified email, which
    // becomes the source of truth for the registry's `accountId`. The
    // CLI path is offered as an explicit, secondary fallback with a
    // visible warning because the CLI session cannot identify the user
    // (`~/.claude.json` is outside the granted bookmark scope) and
    // collapses to a synthetic `cli-local-<hash>` id.
    //
    // `MacOSAPIClient.submitOAuthCode` handles `registry.add` +
    // `registry.setActive`, so the new account becomes active on
    // successful sign-in in both modes (task 3.1).

    private func beginOAuthSignIn() async {
        coordinator.authState.requiresExplicitSignIn = false
        cliRestoreError = nil
        coordinator.client.startOAuthFlow()
    }

    private func beginCLISignIn() async {
        coordinator.authState.requiresExplicitSignIn = false
        cliRestoreError = nil

        isRestoringSession = true
        let start = Date()
        ClaudeCodeKeychainReader.invalidateCache()
        let restored = await coordinator.client.tryRestoreSession(includeCLIFallback: true)
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < 2 {
            try? await Task.sleep(nanoseconds: UInt64((2 - elapsed) * 1_000_000_000))
        }
        if restored {
            // Mark first launch as complete so the app does not reopen
            // this window automatically after the explicit CLI sign-in.
            UserDefaults.standard.set(true, forKey: "hasCompletedFirstLaunch")
            coordinator.onAuthenticated()
            dismissWindow(id: "welcome")
            isRestoringSession = false
        } else {
            isRestoringSession = false
            cliRestoreError = "No active Claude Code CLI session was found. Sign in with Anthropic instead."
        }
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
            // In initial sign-in mode, `authState.isAuthenticated` flips
            // from false to true here and the `.onChange` above will
            // dismiss the window. In add-account mode it is already true,
            // so no change fires - dismiss explicitly to close the window
            // in both modes.
            dismissWindow(id: "welcome")
        } catch {
            signInError = error.localizedDescription
        }
    }
}

// MARK: - FeatureChip
//
// Compact value-prop card used in the welcome view. Three of these line
// up below the menu-bar preview to summarize what Tempo does without
// resorting to a paragraph that overflows the window width.

private struct FeatureChip: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ClaudeCodeTheme.accentMuted)
                    .frame(width: 30, height: 30)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ClaudeCodeTheme.accent)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .background(ClaudeCodeTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(ClaudeCodeTheme.progressTrack, lineWidth: 1)
        )
        .clipShape(.rect(cornerRadius: 12))
    }
}
