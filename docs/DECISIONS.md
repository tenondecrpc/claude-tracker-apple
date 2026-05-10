# Architecture Decisions

Record of significant technical decisions and their tradeoffs.

## 2026-05-03: Security-scoped bookmarks stored in UserDefaults instead of Keychain

### Context

The macOS app needs to store a security-scoped bookmark for the `~/.claude/` folder so the sandboxed app can read local session data. Originally, this bookmark was stored in the macOS Keychain under the service `com.tenondev.tempo.claude.bookmarks`. **That service is now fully retired and unused** - bookmarks live only in `UserDefaults`.

### Problem

Storing the bookmark in the Keychain caused a Keychain access prompt every time the app was reinstalled or updated, even though the bookmark data itself was not a secret. Combined with the prompt for reading the Claude Code CLI keychain item, users saw two consecutive Keychain dialogs on first launch after an update.

### Decision

Move the security-scoped bookmark storage from Keychain to `UserDefaults`.

### Tradeoff Analysis

| Aspect | Keychain | UserDefaults |
|---|---|---|
| Keychain prompt on reinstall/update | Yes (per item) | No |
| Survives full app deletion + reinstall | Yes | No |
| Protected by app sandbox | Yes | Yes |
| Contains secrets/credentials | No | No |
| Usable by other apps | No (bound to bundle ID) | No (bound to sandbox) |
| Implementation complexity | Higher (`SecItem*` APIs) | Lower (`UserDefaults`) |

### Rationale

Security-scoped bookmarks are **not secrets**. They are opaque data blobs that encode a filesystem path and an access token bound to the app's bundle ID. Key benefits of this decision:

1. **No extra Keychain prompt**: Eliminates the second Keychain dialog on reinstall/update. The only remaining prompt is for the **Claude Code CLI keychain item** (`Claude Code-credentials`, owned by the `claude` CLI, not by Tempo). Tempo's own OAuth credentials (`com.tenondev.tempo.claude.oauth`) never trigger a prompt because the app writes to its own bundle-scoped keychain entry.
2. **Sandbox protection is sufficient**: `UserDefaults` for a sandboxed app is already protected by the system. Other apps cannot read it.
3. **Bundle ID binding**: Even if someone extracted the bookmark data, it would only work for this specific app's bundle ID.
4. **Simpler code**: `UserDefaults` API is simpler and less error-prone than `SecItem*` calls.

The one downside is that bookmarks do not survive a full app deletion + reinstall. However, this is acceptable because:
- The user can re-grant folder access via the UI ("Grant Access" button)
- This is a rare scenario (most users update, not delete + reinstall)
- The migration code handles the transition from the old Keychain store automatically

### Migration (removed)

A one-shot migration helper (`UserDefaultsBookmarkStore.migrateFromKeychainIfNeeded`) used to copy any leftover bookmark from the old Keychain service `com.tenondev.tempo.claude.bookmarks` into `UserDefaults` and delete the Keychain entry. It was removed on 2026-05-05: the helper ran on every bookmark resolution, did a `SecItemCopyMatching` that returned `errSecItemNotFound` for all current installs, and was no longer expected to find anything. Any user still on a pre-2026-05-03 build will be re-prompted via the "Grant Access" flow on first need; this is acceptable given the size of the affected cohort.

### Deferred Loading

Alongside this change, bookmark loading was moved from `init()` to on-demand. `ClaudeLocalDBReader` no longer starts loading stats automatically. Instead, `load()` is called when the user opens the stats window (`DetailWindowView`) or preferences (`PreferencesWindowView`). This further improves launch performance and avoids unnecessary I/O for users who never open local stats.

## 2026-05-03: Deferred Keychain access for authentication

### Context

The macOS app needs to access the Keychain to read OAuth credentials. Tempo owns its own OAuth Keychain slots, while Claude Code owns the separate CLI slot (`Claude Code-credentials`). Previously, the app could read the CLI slot during restore, which triggered Keychain prompts before the user had explicitly chosen that login path.

### Problem

On first launch, the Keychain prompt appeared before the Welcome window was shown, creating a confusing experience where the user saw a system dialog without any context about what the app was or why it needed access.

### Decision

Restore only Tempo-owned OAuth credentials automatically. Read the Claude Code CLI Keychain slot only from the explicit "Use existing Claude Code CLI session" action.

### Implementation

- **`MacAuthState.init()`**: No longer checks Keychain. Starts in an unauthenticated state.
- **`onLaunch()`**: Calls `tryRestoreSession()` for Tempo OAuth only. It must not read the Claude Code CLI Keychain slot and must not show a system Keychain prompt.
- **Welcome window**: OAuth sign-in writes Tempo tokens to Tempo's own Keychain slot after the browser flow. The CLI fallback is a separate secondary action that calls `tryRestoreSession(includeCLIFallback: true)`.
- **CLI Keychain reads**: `ClaudeCodeKeychainReader` caches successful CLI reads in memory and uses `kSecUseAuthenticationUIFail` for non-interactive reads, so background work cannot display a Keychain prompt.

### Tradeoff Analysis

| Aspect | Before | After |
|---|---|---|
| First launch UX | Keychain prompt before UI | No CLI Keychain prompt unless user chooses CLI fallback |
| Subsequent launches | Keychain access at init | Tempo OAuth restore only; CLI restore stays explicit |
| Auto-login on return | Yes | Tempo OAuth only |
| User context for permission | None | Clear explanation before prompt |

### Rationale

1. **User trust**: Explaining why the app needs Keychain access before the system prompt appears builds trust and reduces confusion.
2. **No surprise prompts for returning users**: Subsequent launches restore Tempo OAuth silently and leave CLI Keychain access behind the explicit CLI fallback.
3. **Consistent with platform conventions**: Many apps defer permission requests until the feature is first used, providing context at the moment of need.
