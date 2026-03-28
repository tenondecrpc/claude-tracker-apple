## Context

ClaudeTracker currently has OAuth sign-in on iOS, but the UX is poor: the browser doesn't redirect back to the app, requiring manual code paste on iPhone. The reference app "Usage for Claude" (macOS) proves the better pattern — auth happens on the Mac where Claude Code runs, and mobile devices just consume data via iCloud.

The existing iOS `AnthropicAPIClient.swift` implements the full OAuth PKCE flow with paste-code. The macOS version will use the same OAuth endpoints and client ID but adapted for AppKit (`NSWorkspace.shared.open` instead of `UIApplication.shared.open`).

Claude Code stores account info in `~/.claude/.claude.json` (email, display name, account UUID) but does NOT store reusable OAuth tokens. Each app must maintain its own token storage. The reference app claude-usage-bar stores credentials at `~/.config/claude-usage-bar/credentials.json`.

## Goals / Non-Goals

**Goals:**
- macOS menu bar app that handles OAuth login and usage polling
- Two sign-in paths: browser OAuth (paste-code) and "Sign in with Claude Code" (reuses existing session if app already authenticated)
- Write `UsageState` to iCloud Drive as JSON for iOS consumption
- iOS reads from iCloud instead of polling the API directly
- Zero-login experience on iPhone and Apple Watch

**Non-Goals:**
- macOS menu bar UI with popover (like claude-usage-bar) — the macOS app is a background service with minimal UI, not a full dashboard
- Removing existing iOS OAuth code — kept as fallback, just not the primary path
- watchOS changes — watch continues to receive data via WatchConnectivity from iOS
- "Sign in with Email" as a separate flow — both methods use the same OAuth PKCE flow, the difference is whether existing credentials are found on disk

## Decisions

### 1. macOS target type: Menu Bar app with `MenuBarExtra`

**Choice**: SwiftUI `MenuBarExtra` (iOS 16+ / macOS 13+) with a small status window.

**Why**: Lightweight, always-running, no Dock icon. Shows auth status and sign-in/sign-out in the menu. Uses `MenuBarExtra("ClaudeTracker", systemImage:)` with SwiftUI views.

**Alternative considered**: Regular windowed app — too heavy for a background polling service. The menu bar pattern matches claude-usage-bar and "Usage for Claude".

### 2. Credential storage: File-based at `~/.config/claude-tracker/credentials.json`

**Choice**: Store `access_token`, `refresh_token`, `expiresAt`, and `scopes` in a JSON file with `0600` permissions, in `~/.config/claude-tracker/`.

**Why**: Matches the claude-usage-bar pattern. Simpler than Keychain for a macOS-only credential that doesn't need iCloud sync. File permissions provide adequate security for a single-user desktop app.

**Alternative considered**: macOS Keychain — more secure but adds complexity (SecItem APIs, access control). Claude Code itself doesn't use Keychain. File-based is sufficient for a personal project.

### 3. iCloud transport: JSON file at known path

**Choice**: macOS writes `usage.json` to `~/Library/Mobile Documents/com~apple~CloudDocs/ClaudeTracker/usage.json`. iOS reads it via `NSMetadataQuery`.

**Why**: Same transport mechanism planned for the stop-hook pipeline (`latest.json`). Keeps all cross-device data in one iCloud folder. `NSMetadataQuery` on iOS already handles download status and file coordination.

**Payload**: The JSON file contains the full `UsageState` struct encoded as JSON, overwritten on each poll.

### 4. "Sign in with Claude Code" behavior

**Choice**: On launch, check if `~/.config/claude-tracker/credentials.json` exists with valid (non-expired) tokens. If yes, skip OAuth flow and go straight to polling. The button label "Sign in with Claude Code" signals to users that this uses their Claude account (the same one Claude Code uses), not that it literally reads Claude Code's tokens.

**Why**: Claude Code does NOT expose reusable OAuth tokens. `~/.claude/.claude.json` has account metadata (email, name) but no access/refresh tokens. Each app must manage its own OAuth tokens. However, we CAN read the email from `.claude.json` to pre-fill or display the account name.

**Alternative considered**: Reading tokens from Claude Code's internal storage — not possible, they don't store tokens in an accessible format.

### 5. Polling on macOS, reading on iOS

**Choice**: The macOS app polls `GET /api/oauth/usage` every 15 minutes and writes the result to iCloud. The iOS app watches the iCloud file and relays `UsageState` to the watch via `WatchConnectivity`.

**Why**: Centralizes API calls on the always-on Mac. iOS doesn't need its own auth flow. The iCloud file acts as a simple pub/sub mechanism.

**Data flow**:
```
macOS (poll API → write usage.json to iCloud)
    ↓ iCloud sync
iOS (NSMetadataQuery → read usage.json → WatchConnectivity)
    ↓ transferUserInfo
watchOS (TokenStore → dashboard ring)
```

## Risks / Trade-offs

**[Risk] Mac not running → stale data on watch**
→ Mitigation: iOS shows "last updated" timestamp. Watch ring shows stale data with visual indicator (e.g., dimmed ring or "Xh ago" label). Acceptable for v1 — the Mac is almost always on when using Claude Code.

**[Risk] iCloud sync delay**
→ Mitigation: iCloud Drive typically syncs within seconds on the same network. For usage data updated every 15 minutes, even a 1-2 minute sync delay is acceptable.

**[Risk] File-based credential storage less secure than Keychain**
→ Mitigation: File permissions `0600` prevent other users from reading. This is a personal project on a single-user Mac. Same approach used by claude-usage-bar without issues.

**[Risk] Two polling apps could conflict**
→ Mitigation: ClaudeTracker uses a 15-minute interval (claude-usage-bar uses 60s). Combined, this is well within API rate limits. No coordination needed.

## Open Questions

- Should the macOS app also display usage in the menu bar (like claude-usage-bar), or remain a pure background service? Starting with background-only, can add menu bar display later.
