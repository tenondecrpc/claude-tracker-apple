# Architecture Decisions

Record of significant technical decisions and their tradeoffs.

## 2026-05-03: Security-scoped bookmarks stored in UserDefaults instead of Keychain

### Context

The macOS app needs to store a security-scoped bookmark for the `~/.claude/` folder so the sandboxed app can read local session data. Previously, this bookmark was stored in the macOS Keychain (`com.tenondev.tempo.claude.bookmarks`).

### Problem

Storing the bookmark in the Keychain caused a Keychain access prompt every time the app was reinstalled or updated, even though the bookmark data itself was not a secret. Combined with the OAuth credential Keychain prompt, users saw two consecutive Keychain dialogs on first launch after an update.

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

1. **No extra Keychain prompt**: Eliminates the second Keychain dialog on reinstall/update. Only the OAuth credential prompt remains (which is legitimate, as it contains actual tokens).
2. **Sandbox protection is sufficient**: `UserDefaults` for a sandboxed app is already protected by the system. Other apps cannot read it.
3. **Bundle ID binding**: Even if someone extracted the bookmark data, it would only work for this specific app's bundle ID.
4. **Simpler code**: `UserDefaults` API is simpler and less error-prone than `SecItem*` calls.

The one downside is that bookmarks do not survive a full app deletion + reinstall. However, this is acceptable because:
- The user can re-grant folder access via the UI ("Grant Access" button)
- This is a rare scenario (most users update, not delete + reinstall)
- The migration code handles the transition from the old Keychain store automatically

### Migration

The code includes a one-time migration (`UserDefaultsBookmarkStore.migrateFromKeychainIfNeeded`) that reads any existing bookmark from the old Keychain store, saves it to `UserDefaults`, and removes the Keychain entry. This ensures existing users do not lose their bookmark after updating.

### Deferred Loading

Alongside this change, bookmark loading was moved from `init()` to on-demand. `ClaudeLocalDBReader` no longer starts loading stats automatically. Instead, `load()` is called when the user opens the stats window (`DetailWindowView`) or preferences (`PreferencesWindowView`). This further improves launch performance and avoids unnecessary I/O for users who never open local stats.

## 2026-05-03: Deferred Keychain access for authentication

### Context

The macOS app needs to access the Keychain to read OAuth credentials (either Tempo's own OAuth tokens or Claude Code CLI tokens). Previously, this access happened during `MacAuthState.init()` and `onLaunch()`, which triggered Keychain prompts before the app's UI was visible.

### Problem

On first launch, the Keychain prompt appeared before the Welcome window was shown, creating a confusing experience where the user saw a system dialog without any context about what the app was or why it needed access.

### Decision

Defer all Keychain access until the user explicitly initiates sign-in via the Welcome window.

### Implementation

- **`MacAuthState.init()`**: No longer checks Keychain. Starts in an unauthenticated state.
- **`onLaunch()`**: Uses a `UserDefaults` flag (`hasCompletedFirstLaunch`) to distinguish first launch from subsequent launches:
  - **First launch**: Shows the Welcome window without touching Keychain. The user reads the explanation and clicks "Sign in with Claude Code", which is when `tryRestoreSession()` is called and the Keychain prompt appears.
  - **Subsequent launches**: Calls `tryRestoreSession()` immediately. Since the user already granted "Always Allow" on first launch, this succeeds silently without any prompts. If credentials are expired or missing, falls back to showing the Welcome window.
- **Welcome window**: Includes an explanation card describing what the Keychain permission is for before the sign-in button.
- **After successful sign-in**: Sets `hasCompletedFirstLaunch = true` so future launches auto-restore.

### Tradeoff Analysis

| Aspect | Before | After |
|---|---|---|
| First launch UX | Keychain prompt before UI | Welcome window with explanation, then prompt on button click |
| Subsequent launches | Keychain access at init | Keychain access at launch (silent, no prompt) |
| Auto-login on return | Yes | Yes (same behavior) |
| User context for permission | None | Clear explanation before prompt |

### Rationale

1. **User trust**: Explaining why the app needs Keychain access before the system prompt appears builds trust and reduces confusion.
2. **No regression for returning users**: Since "Always Allow" was already granted, subsequent launches still auto-login silently.
3. **Consistent with platform conventions**: Many apps defer permission requests until the feature is first used, providing context at the moment of need.
