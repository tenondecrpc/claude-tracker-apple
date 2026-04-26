## 0. Fix the Claude Code profile path

- [x] 0.1 In `Tempo macOS/MacOSAPIClient.swift`, change `appendingPathComponent(".claude/.claude.json")` in `ClaudeCodeProfile.load()` to `appendingPathComponent(".claude.json")` so the read targets the actual file on disk (matches `claude-usage-bar/macos/Sources/ClaudeUsageBar/UsageService.swift:325-340`).
- [x] 0.2 Sanity-check by adding a temporary `print` and confirming `MacAuthState.init` resolves `accountEmail` to a non-nil value on a machine that has Claude Code signed in. Remove the print before committing.

## 1. Single source of truth for "active Claude Code session"

- [x] 1.1 In `Tempo macOS/MacOSAPIClient.swift` (or a new sibling file in the macOS target), introduce a `DetectedClaudeAccount` value type with `emailAddress: String?`, `displayName: String?`, and a computed `label: String? { emailAddress ?? displayName }`.
- [x] 1.2 Add `static func load() -> DetectedClaudeAccount?` that reads `~/.claude.json`, decodes `oauthAccount.emailAddress` and `oauthAccount.displayName`, returns `nil` when both are empty/missing or the file is unreadable, and never throws to the caller.
- [x] 1.3 Add `static var isActive: Bool { load() != nil }` as the canonical "active Claude Code session" check that every surface in the app uses (welcome window, menu bar popover, coordinator).
- [x] 1.4 Replace any in-target callers that previously read the Claude Code profile JSON inline (including `MacAuthState.init`'s use at `MacOSAPIClient.swift:41`) with calls to the new helper, so the file read happens in exactly one place.

## 2. Welcome window: Claude-Code-aware decision tree

- [x] 2.1 In `Tempo macOS/WelcomeWindow.swift`, replace the body of the "Sign in with Claude Code" button action (currently `WelcomeWindow.swift:57-74`) with the four-step decision tree from design.md Decision 3: probe `DetectedClaudeAccount.isActive`, then either `tryRestoreSession()` then OAuth-on-failure, or OAuth directly when no session.
- [x] 2.2 Preserve the existing minimum-2-second restoring-session UI delay, but only on the `tryRestoreSession()` branch (not on the direct-OAuth branch when no Claude Code session exists).
- [x] 2.3 Hold the detected account in `@State var detectedAccount: DetectedClaudeAccount?` populated in `.onAppear` so it refreshes whenever the welcome window appears (covers the sign-out -> welcome-window-reopens path).
- [x] 2.4 When `detectedAccount?.label != nil`, render a small caption beneath the button reading e.g. "Detected: <label>" (use `ClaudeCodeTheme.textSecondary`, `.caption` font, matching the visual weight of the existing subtitle copy).
- [x] 2.5 When `detectedAccount?.label == nil`, render no caption and keep today's button copy/visuals exactly as they are.

## 3. Menu bar popover: same affordance for consistency

- [x] 3.1 In `Tempo macOS/SignInView.swift -> NotSignedInMenuView`, hold the detector in `@State var detectedAccount: DetectedClaudeAccount?` populated in `.onAppear` so it refreshes each time the popover opens.
- [x] 3.2 When `detectedAccount?.label != nil`, the existing "Sign In" button SHALL still open the welcome window (current behavior unchanged), but a small caption beneath the button SHALL surface "Detected: <label>" so the menu surface is consistent with the welcome window.
- [x] 3.3 When `detectedAccount?.label == nil`, render today's UI unchanged.

## 4. Sign-out -> welcome window flag wiring

- [x] 4.1 In `Tempo macOS/TempoMacApp.swift`, on the macOS coordinator (`MacAppCoordinator`), observe `coordinator.authState.requiresExplicitSignIn` (using the `@Observable` change-tracking already in the project) and, when it transitions to true, dispatch to the main actor and call `openWindow(id: "welcome")`.
- [x] 4.2 In the same observer, if a menu bar popover with authenticated state is open, close it (or rely on its existing `coordinator.authState.isAuthenticated` binding to flip to `NotSignedInMenuView`).
- [x] 4.3 Reset `coordinator.authState.requiresExplicitSignIn = false` immediately after `openWindow(id: "welcome")` is called so the flag is one-shot and does not re-fire on subsequent observed changes.
- [x] 4.4 Verify `MacOSAPIClient.signOut()` (`MacOSAPIClient.swift:292-297`) still sets the flag (it does today); do not duplicate that call elsewhere.

## 5. Verification

- [x] 5.1 Build the `Tempo macOS` scheme in Xcode and confirm no warnings/errors are introduced by exposing the detector type.
- [ ] 5.2 Manually verify (with a real signed-in Claude Code install + Tempo not yet authorized): open the welcome window, see "Detected: <your-email>" beneath the button, click the button, observe browser opening to the Anthropic authorization URL.
- [ ] 5.3 Manually verify (with a real signed-in Claude Code install + Tempo already authorized from a prior run): open the welcome window, see the caption, click the button, observe the welcome window dismissing without opening the browser (restored session path).
- [ ] 5.4 Manually verify the no-Claude-Code path: temporarily rename `~/.claude.json` (or hand-edit it to remove `oauthAccount`), reopen the welcome window, confirm no caption is rendered, click the button, observe the browser opening directly without a "restoring..." pause. Restore the file afterwards.
- [ ] 5.5 Manually verify sign-out: from a signed-in state, click "Sign Out" in the menu, confirm (a) credentials are deleted, (b) the welcome window appears automatically, (c) the welcome window's detected-account caption reflects the live state of `~/.claude.json`, (d) `requiresExplicitSignIn` is back to false (e.g., re-trigger an unrelated state change and confirm the welcome window does not re-open).
- [ ] 5.6 Manually verify the post-sign-in account label (`MacAuthState.accountEmail`) now renders the user's email in the menu bar header on a machine that already had Tempo credentials before this change (the path-fix side-effect from task 0.1).
- [x] 5.7 Confirm `Tempo macOS/Tempo macOS.entitlements` is unchanged in the diff.
- [x] 5.8 Confirm no new code reads `Claude Code-credentials` from the macOS Keychain (grep for `SecItemCopyMatching`, `kSecClassGenericPassword`, and the literal string `Claude Code-credentials` in the diff and expect zero new matches).
- [ ] 5.9 Capture a before/after screenshot pair of the welcome window (with and without a detected Claude Code session) for the PR description per the AGENTS.md UI verification guidance.
