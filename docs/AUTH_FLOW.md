# Tempo Authentication Flow

This document describes the current macOS authentication behavior.

## Credential Sources

Tempo has two possible credential sources for Anthropic usage API calls:

1. **Tempo OAuth credentials** stored in the macOS Keychain under service `com.tenondev.tempo.claude.oauth`.
2. **Claude Code CLI access token** read from the macOS Keychain item `Claude Code-credentials`.

Tempo OAuth is the preferred source. Claude Code CLI credentials are a read-only fallback.

## Restore Order

On launch and when the user clicks "Sign in with Claude Code", Tempo restores authentication in this order:

1. Load Tempo OAuth credentials from Keychain.
2. If the Tempo access token is valid, use it.
3. If the Tempo access token is expired, refresh it with Tempo's own refresh token and save the refreshed Tempo credentials back to Keychain.
4. If Tempo OAuth credentials are unavailable or cannot be refreshed, read Claude Code CLI credentials.
5. Use Claude Code CLI credentials only when the CLI access token is still fresh.
6. If no valid Tempo credentials and no fresh Claude Code CLI access token exist, start the Tempo OAuth browser flow.

## Request Order

For usage API requests, Tempo uses this order:

1. Tempo OAuth credentials.
2. Fresh Claude Code CLI access token fallback.

If a Tempo OAuth request returns 401, Tempo refreshes only Tempo OAuth credentials and retries once.

If a Claude Code CLI request returns 401, Tempo does not refresh Claude Code credentials. It falls back to Tempo OAuth if available; otherwise the request fails and the user must sign in through Tempo OAuth.

## Claude Code Isolation

Tempo must not write, delete, or refresh Claude Code's own credentials.

Allowed:

- Read the Claude Code Keychain item to obtain a fresh access token.
- Read `~/.claude.json` to display the detected Claude Code account label.
- Read `~/.claude/` project JSONL files for local session stats after the user grants folder access.

Not allowed:

- Use Claude Code's refresh token.
- Write a refreshed token back to Claude Code's Keychain item.
- Delete Claude Code's Keychain item.
- Treat local Claude Code session data as the source for account utilization.

## Identity Convergence Across CLI and OAuth

The same person using Claude Code CLI today and completing Tempo OAuth tomorrow under the same Anthropic email MUST be recognized as a single account by Tempo. Tempo does not create a second row in `AccountRegistry`, a second per-account iCloud directory, or a second Keychain credential slot for that user.

### How convergence works

Both the explicit CLI sign-in path and the Tempo OAuth exchange path build the `accountId` the same way:

1. Load `~/.claude.json` via `DetectedClaudeAccount.load()`.
2. Read `oauthAccount.emailAddress`.
3. Canonicalize through `AccountIdentifier.canonicalize(email:)` (NFC + trim + lowercase).
4. Use the canonical string as `accountId`.

Because both paths key off the same canonical email, the derived `accountId` is byte-identical. `AccountRegistry.add` is idempotent and updates the existing row in place when the `accountId` already exists, so the second path never creates a duplicate.

The per-account iCloud directory (`Tempo/accounts/<accountId>/`), the Keychain credential slot (`kSecAttrAccount = <accountId>`), and the widget snapshot all key off the same `accountId`, so identity convergence holds end to end.

### Sandbox requirement

Reading `~/.claude.json` from an App-Sandboxed build requires a narrow temporary-exception entitlement:

```xml
<key>com.apple.security.temporary-exception.files.home-relative-path.read-only</key>
<array>
    <string>/.claude.json</string>
</array>
```

This entitlement lives in `Tempo macOS/Tempo macOS.entitlements`. It is read-only and scoped to that exact file. Removing or misnaming it causes `DetectedClaudeAccount.load()` to silently return `nil`, which breaks identity convergence for explicit CLI sign-in: the CLI path falls back to a synthetic `cli-local-<hash>` id instead of the canonical email-derived id.

### Fallback: synthetic `cli-local-<hash>` id

When `~/.claude.json` cannot be read (entitlement missing, file absent, or the `oauthAccount` block does not expose an email), the explicit CLI path in `MacOSAPIClient.tryRestoreSession(includeCLIFallback: true)` falls back to `AccountIdentifier.cliFallbackAccountId(from:)`, which hashes the refresh token into a deterministic id of the form `cli-local-<8 hex>`. The app remains usable on that synthetic id, but identity convergence is deferred until the canonical email becomes readable.

### Migration of a synthetic id to the canonical id

As soon as the canonical email becomes readable (for example, after the sandbox entitlement is restored, or after the user completes Tempo OAuth), the code migrates any outstanding `cli-local-<hash>` row to the canonical id:

- `MacOSAPIClient.tryRestoreSession(includeCLIFallback: true)` CLI branch: when it resolves a canonical email-backed id, it scans `AccountRegistry` for any `cli-local-<hash>` row and removes it via `AccountRemovalService`. The canonical row is then added in the usual way.
- `MacOSAPIClient.submitOAuthCode(_:)` exchange path: on successful OAuth, the newly-built `Account` uses the canonical id from `makeAccount(from:)`. The same `cli-local-<hash>` sweep runs so CLI-first / OAuth-later flows converge on a single registry row.

`AccountRemovalService.removeAccount(accountId:)` handles the full teardown of the synthetic row: Keychain credential slot (if one was ever written, which it typically was not for a CLI-only row), per-account iCloud directory, registry entry, and `accounts/index.json` mirror. The migration is idempotent: calling it with no synthetic rows present is a no-op.

### User-visible effect

- Choose the explicit CLI fallback while CLI credentials exist and the `~/.claude.json` entitlement is working: the app registers `tenondecrpc@gmail.com` (for example) as the `accountId`. Usage polling, iCloud writes, and widget snapshots all key off that canonical id.
- Later complete Tempo OAuth under the same email: the OAuth path derives the same canonical `accountId`, so `registry.add` updates the existing row in place. The iCloud directory, widget snapshot, and usage history persist across the transition.
- Start with CLI credentials while the `~/.claude.json` entitlement is missing (regression scenario): the app registers `cli-local-abcd1234`. When the entitlement is restored or the user completes Tempo OAuth under the canonical email, the code migrates the `cli-local-abcd1234` row out and replaces it with the canonical id. The migration is recorded in the `AuthTrace` DevLog stream:
  ```
  Migrating synthetic CLI account to canonical email-backed id oldAccountId=cli-local-abcd1234 newAccountId=tenondecrpc@gmail.com
  ```

### Guardrails

- Neither the explicit CLI sign-in path nor the OAuth exchange ever writes to the CLI's own Keychain item or to `~/.claude.json`. Those remain owned by the Claude Code CLI.
- The synthetic `cli-local-<hash>` id is stable across relaunches for the same CLI session because it hashes the CLI refresh token. This keeps the user on a single synthetic row until the canonical email becomes readable, rather than creating a new synthetic row on every launch.
- The `AccountRemovalService` path is best-effort for iCloud: on a fresh install where the synthetic row never produced an iCloud directory, the directory-delete step is a silent no-op, which is correct.

## Sign-Out

Tempo sign-out deletes only Tempo OAuth credentials and clears Tempo's local polling state, including persisted rate-limit backoff. It does not change the Claude Code terminal session.

Claude Code sign-out removes the CLI Keychain item. If Tempo has valid OAuth credentials, it continues using `source=webOAuth`. If Tempo has no valid OAuth credentials, it asks the user to sign in through Tempo OAuth.
