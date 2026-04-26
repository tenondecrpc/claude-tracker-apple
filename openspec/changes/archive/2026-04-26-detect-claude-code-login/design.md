## Context

Tempo macOS is a sandboxed menu bar app. Its OAuth PKCE flow against `claude.ai/oauth/authorize` produces tokens that are stored in `~/.config/tempo-for-claude/credentials.json` (`Tempo macOS/MacOSAPIClient.swift`, `Tempo macOS/CredentialStore.swift`). Claude Code, installed separately, stores its own OAuth tokens in the macOS Keychain under the generic-password label `Claude Code-credentials` (verified on the developer's machine via `security find-generic-password -l "Claude Code-credentials"`). The two credential surfaces are independent; `AGENTS.md` forbids collapsing the OAuth-usage pipeline with the local-session pipeline.

### Current welcome-window flow

`Tempo macOS/WelcomeWindow.swift:57-74` already exposes a "Sign in with Claude Code" button. Its current action:

1. Calls `coordinator.client.tryRestoreSession()` (`MacOSAPIClient.swift:204-218`), which only inspects Tempo's own `~/.config/tempo-for-claude/credentials.json` and refreshes it if expired.
2. If restore fails, calls `coordinator.client.startOAuthFlow()` (web OAuth handshake).

The button's name suggests a Claude-Code-aware behavior, but the implementation has no notion of Claude Code's session - it is just "restore Tempo creds, otherwise OAuth".

### Pre-existing path bug

`MacOSAPIClient.swift:54-62` defines a private `ClaudeCodeProfile` decoder that reads `~/.claude/.claude.json`. The actual file lives at `~/.claude.json` (home root). On the developer's machine, `~/.claude.json` is a 35KB owner-only file with `oauthAccount.emailAddress = "tenondecrpc@gmail.com"`, while `~/.claude/.claude.json` does not exist. The reference project `claude-usage-bar` reads the correct path in `UsageService.swift:325-340`. Because of the bug, `MacAuthState.accountEmail` (set at `MacOSAPIClient.swift:41`) silently never resolves; the post-sign-in account label is dormant on every install today. We fix it in this change because the new Claude-Code-aware welcome flow depends on the read actually succeeding.

### Existing logout signal

`MacOSAPIClient.signOut()` (`MacOSAPIClient.swift:292-297`) sets `MacAuthState.requiresExplicitSignIn = true`. No surface currently observes this flag, so after sign-out the menu bar drops back to `NotSignedInMenuView` with no automatic transition to the welcome window. The user explicitly asked for the welcome window to come back on logout, so this change wires the existing flag to the existing welcome window.

### Reference implementation: `claude-usage-bar`

`claude-usage-bar` (`/Users/tenonde/Projects/open-sources/claude-usage-bar`) solves the same usage-display problem. Its OAuth flow is identical to Tempo's (same `client_id` `9d1c250a-e61b-44d9-88ed-5944d1962f5e`, same authorize/token endpoints, same scopes, same beta header, same redirect URI). For Claude-Code-session integration:

- `UsageService.swift:325-340` (`loadLocalProfile`) reads `~/.claude.json` (correct path) and extracts `oauthAccount.emailAddress` / `oauthAccount.displayName`.
- `UsageService.swift:299-322` (`fetchProfile`) calls `loadLocalProfile()` first, falling back to `https://api.anthropic.com/api/oauth/userinfo` when local is unavailable.

`claude-usage-bar` also has no second login mechanism. It does not read Claude Code's Keychain item. Its "Claude Code session" integration is purely a label-source enhancement on top of the same OAuth handshake. This change adopts the same pattern.

## Goals / Non-Goals

**Goals:**

- Fix the `~/.claude/.claude.json` -> `~/.claude.json` path so the existing decoder returns a value on real installs.
- Define and implement a single source of truth for "is there an active Claude Code session?" - a static helper that returns `true` iff `~/.claude.json` has a populated `oauthAccount`.
- Rewire the welcome window's "Sign in with Claude Code" button to: (1) probe Claude Code's session, (2) restore Tempo's stored credentials if both signals agree, (3) start OAuth otherwise, (4) start OAuth directly when no Claude Code session exists.
- Surface the detected Claude Code email/display name on the welcome window when a session is detected, so the user understands which account will be authorized.
- Wire `MacAuthState.requiresExplicitSignIn` to automatically open the welcome window after `signOut()` and clear the flag once the welcome window is presented.

**Non-Goals:**

- Reading or importing Claude Code's tokens from the macOS Keychain (`Claude Code-credentials`). Sandboxed Tempo cannot do this without dropping the sandbox or shipping a non-sandboxed helper, both of which are out of scope and explicitly forbidden by `AGENTS.md`.
- Treating Claude Code's session presence as authorization for Tempo to make API calls without its own OAuth handshake. Authorization remains gated on `CredentialStore.load()` returning valid Tempo credentials.
- Pre-filling the OAuth authorization URL with `login_hint` or any other account hint. Not documented by Anthropic; deferred.
- Adding the `https://api.anthropic.com/api/oauth/userinfo` remote-profile fallback that `claude-usage-bar` uses. Useful follow-up; orthogonal to this change.
- Polling or watching `~/.claude.json` for changes. Re-read on view appearance and on the welcome-window-open path is sufficient.
- Replacing Tempo's OAuth client ID, redirect URI, scopes, token endpoint, refresh behavior, or stored-credential location.
- Touching iOS or watchOS targets. The Claude Code config file lives only on the host Mac; iOS/watchOS continue to receive the email Tempo macOS already relays.

## Decisions

### Decision 1: "Active Claude Code session" = readable `~/.claude.json` with populated `oauthAccount`

Tempo cannot read Claude Code's actual access/refresh tokens from the macOS Keychain because the two apps live under different team-prefixed access groups; the macOS sandbox blocks cross-app keychain reads. The only Claude-Code-specific signal a sandboxed Tempo can read is the on-disk profile file `~/.claude.json`. This file is rewritten by Claude Code on login/logout and contains a populated `oauthAccount` when (and only when) the user is signed in. We therefore define an "active Claude Code session" as: `~/.claude.json` is readable AND `oauthAccount.emailAddress || oauthAccount.displayName` is non-empty.

This is necessarily an *advisory* signal: if the user has signed out of Claude Code but the JSON file still has stale `oauthAccount` data (e.g., between writes), we may briefly classify the session as active when it is not. The downstream consequence is a misleading button label - the user clicks "Sign in with Claude Code (detected: a@example.com)" and proceeds to a normal OAuth handshake. No tokens are leaked, no auth state is confused. Acceptable.

**Alternative considered:** spawn a non-sandboxed helper (XPC service or login item) that calls `security find-generic-password -s "Claude Code-credentials" -w` and pipes the JSON-encoded credential blob back to the main app. Rejected because (a) it requires shipping and signing a second binary, (b) it triggers a Keychain access prompt the first time and is fragile across Claude Code updates, (c) it is materially out of scope for what the user described, and (d) `AGENTS.md` is explicit that OAuth credentials must not move outside Tempo's own credential store.

**Alternative considered:** drop the macOS sandbox entirely so Tempo can read the Keychain item directly. Rejected because the sandbox is required for the iCloud and app-group entitlements that the rest of the product depends on (`Tempo macOS/Tempo macOS.entitlements`), and removing it is a risky, far-reaching change that should be its own discussion.

### Decision 0: Fix the `~/.claude/.claude.json` -> `~/.claude.json` path bug as part of this change

The existing `ClaudeCodeProfile.load()` reads the wrong path; the new welcome flow depends on the read actually returning a value. Folding the one-line path correction into the same change avoids a release in which the new UI sits on top of a still-broken decoder. The reference `claude-usage-bar/macos/Sources/ClaudeUsageBar/UsageService.swift:325-340` reads the correct path; we mirror it.

**Alternative considered:** ship the path fix as a prerequisite change. Rejected because the two changes share the same code path, the same review surface, and the same manual verification step ("does the email render?"). Splitting them would double review cost without adding safety.

### Decision 2: Promote `ClaudeCodeProfile` to a view-callable helper with a `hasActiveSession` shortcut

Both the welcome window and the menu bar popover need to ask "is there an active Claude Code session, and what is its label?" without each duplicating the file read. We introduce a small value type, e.g.:

```swift
struct DetectedClaudeAccount {
    let emailAddress: String?
    let displayName: String?
    var label: String? { emailAddress ?? displayName }

    static func load() -> DetectedClaudeAccount?  // returns nil iff label would be empty
    static var isActive: Bool { load() != nil }
}
```

`load()` reads `~/.claude.json` synchronously, decodes `oauthAccount`, returns `nil` on any failure. `isActive` is the boolean shortcut used by the welcome flow's branch logic. Views call these on `.onAppear` (or directly in the button action), so the value reflects current state at the moment the surface is shown, with no timers or file watchers.

**Alternative considered:** make this an `@Observable` field on `MacAuthState` refreshed by an `NSMetadataQuery` watcher. Rejected for the same reasons as in the previous draft - watcher lifecycle complexity is not justified for a value that only matters at moments of explicit user interaction.

**Alternative considered:** put the helper in `Shared/`. Rejected because `~/.claude.json` only exists on the Mac that runs Claude Code; iOS and watchOS have no use for it, and `AGENTS.md` keeps macOS-specific home-directory access in the macOS target.

### Decision 3: Welcome button decision tree (replaces `WelcomeWindow.swift:57-74`)

```
on tap "Sign in with Claude Code":
  let claudeCodeActive = DetectedClaudeAccount.isActive
  if claudeCodeActive:
    // user has Claude Code signed in
    let restored = await coordinator.client.tryRestoreSession()
    if restored:
      coordinator.onAuthenticated()
      dismissWindow(id: "welcome")
    else:
      // user has Claude Code, but Tempo has no creds yet -> OAuth handshake
      coordinator.client.startOAuthFlow()
  else:
    // no Claude Code session at all -> direct web OAuth
    coordinator.client.startOAuthFlow()
```

The button's visible state SHALL reflect detection: when `claudeCodeActive`, render a small caption beneath the button with the detected label (e.g., "Detected: tenondecrpc@gmail.com"). When not, the existing button text is sufficient.

The minimum-2-second restoring-session UI behavior already in the file (`WelcomeWindow.swift:62-66`) is preserved for the `tryRestoreSession()` branch only.

**Alternative considered:** force `tryRestoreSession()` regardless of Claude Code presence (today's behavior). Rejected because the user's spec is explicit: when no Claude Code session exists, go straight to web OAuth without the "restoring..." pause.

**Alternative considered:** require the detected email to MATCH whatever `MacAuthState.accountEmail` is restored from. Rejected because Tempo cannot independently verify the match (tokens belong to whichever account the OAuth handshake authorized, which might differ from the local profile if the user has multiple Anthropic accounts) and the discrepancy already surfaces post-sign-in via the `accountEmail` label.

### Decision 4: Wire `MacAuthState.requiresExplicitSignIn` to open the welcome window automatically

`MacOSAPIClient.signOut()` already sets the flag. We extend `MacAppCoordinator` (in `Tempo macOS/TempoMacApp.swift`) to observe `MacAuthState.requiresExplicitSignIn` via the existing `@Observable` mechanism and:

1. When the flag transitions to `true`, dispatch to the main actor and call `openWindow(id: "welcome")`.
2. Close any open menu bar popover that depends on authenticated state (so the user is not stuck in a stale popover).
3. Clear the flag the moment the welcome window is presented (so it does not re-open on subsequent state changes).

The flag itself does not need to persist across launches; on launch, `MacAuthState.init` already reflects the absence of credentials and opens the appropriate first surface.

**Alternative considered:** push the welcome-window-opening logic into `signOut()` itself. Rejected because `signOut()` lives in `MacOSAPIClient`, which has no reference to SwiftUI's `openWindow` environment - keeping the flag-then-observer pattern preserves layering.

**Alternative considered:** add a separate `presentWelcome` flag with different semantics. Rejected because `requiresExplicitSignIn` already exists, already has the right semantics ("user must sign in again before they can use the app"), and is already set by `signOut()`. Adding a second flag would invite divergence.

## Risks / Trade-offs

- **Risk:** A user has Claude Code signed in as account A but wants Tempo on account B. -> **Mitigation:** the OAuth handshake still happens (we never bypass it), so the user sees the Anthropic consent screen and can pick whichever account they want. The detected label on the button is advisory only.
- **Risk:** `~/.claude.json` schema drift removes or relocates `oauthAccount`. -> **Mitigation:** `DetectedClaudeAccount.load()` returns `nil` on any decode failure; the welcome button falls through to the direct-OAuth branch with no user-visible breakage.
- **Risk:** Sandbox prompts the user when Tempo reads `~/.claude.json` from the welcome window. -> **Mitigation:** the file lives in the user's home directory and is read with `Data(contentsOf:)`. The reference `claude-usage-bar` performs the same read without entitlement changes; we expect the same behavior. If a one-time prompt does appear, it does not block authentication.
- **Risk:** Path-fix re-enables `MacAuthState.accountEmail` for users who are already signed in, so an email string suddenly starts appearing in the menu after upgrade. -> **Mitigation:** intended behavior of the existing (dormant) feature; call out in the PR description so reviewers are not surprised.
- **Risk:** `requiresExplicitSignIn` may already be set from prior unrelated sign-out paths and trigger an unwanted welcome window on launch. -> **Mitigation:** observe the flag's transitions, not its initial value; clear it as soon as the welcome window is presented.
- **Trade-off:** Re-reading `~/.claude.json` on every appearance duplicates IO compared to a cached value, but the file is small, the read happens only at moments of user interaction, and the freshness benefit (sign in to Claude Code, then open Tempo) is worth the few milliseconds.
- **Trade-off:** We deliberately defer the `https://api.anthropic.com/api/oauth/userinfo` remote-profile fallback. Tempo users without a Claude Code install therefore continue to see no account label even after sign-in. Becomes its own follow-up change if desired.
- **Trade-off:** "Active Claude Code session" detection is necessarily best-effort because we cannot read Claude Code's tokens. The signal is a profile JSON, not an authentication proof. Acceptable because no privileged action is gated on it - the worst case is a misleading button label.
