## Why

The current OAuth sign-in lives on the iOS app, but the Mac is where Claude Code runs and where credentials already exist. The reference app "Usage for Claude" proves this pattern: macOS handles auth + polling and syncs data via iCloud — mobile devices just consume. Moving OAuth to a macOS target eliminates the awkward paste-code UX on iPhone (browser doesn't redirect back) and centralizes auth where the user actually works. The iOS and watchOS apps become pure data consumers via iCloud, with no login required.

## What Changes

- **New macOS target** in `Tempo.xcodeproj` — a menu bar app (or window) that handles OAuth sign-in and usage polling
- **Two sign-in methods on macOS**:
  1. "Sign in with Claude Code" — detects existing Claude Code OAuth credentials on disk and reuses them (zero-friction for CLI users)
  2. "Sign in with Email" — browser-based OAuth PKCE flow with paste-code (same as current iOS implementation but using `NSWorkspace.shared.open`)
- **macOS polls the Anthropic usage API** and writes `UsageState` as JSON to iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs/Tempo/usage.json`)
- **iOS app reads `usage.json` from iCloud** via `NSMetadataQuery` instead of polling the API directly — no OAuth login needed on iOS
- **iOS relays `UsageState` to watchOS** via `WatchConnectivity` (unchanged)
- **BREAKING**: iOS OAuth sign-in flow becomes unused (kept in code for now but not the primary path)

## Capabilities

### New Capabilities
- `macos-oauth`: macOS-specific OAuth client with two sign-in methods (Claude Code credentials reuse + browser paste-code flow), Keychain storage, and token refresh — adapted from the existing `anthropic-oauth` spec for AppKit/macOS context
- `macos-usage-writer`: macOS daemon that polls the usage API and writes `UsageState` JSON to iCloud Drive on a schedule
- `icloud-usage-sync`: iCloud Drive as the data transport layer — macOS writes, iOS reads — replacing direct API polling on iOS

### Modified Capabilities
- `usage-polling`: Polling now happens on macOS (not iOS). iOS no longer polls the API directly; it reads from iCloud instead. The polling logic itself (interval, backoff, mapping) remains the same.

## Impact

- **New Xcode target**: macOS app target added to `Tempo.xcodeproj`
- **Shared code**: `UsageState` model (in `Shared/`) used by macOS writer and iOS reader
- **iCloud entitlement**: Required on both macOS (write) and iOS (read) targets
- **iOS `AnthropicAPIClient.swift`**: Retained but demoted — macOS is now the primary auth path
- **No watchOS changes**: Watch continues to receive `UsageState` via `WatchConnectivity` from iOS
- **Dependencies**: No new external dependencies — uses Foundation, AppKit, Security, CryptoKit
