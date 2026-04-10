## Why

The current macOS menu bar app has a minimal, default-styled SwiftUI UI — a basic sign-in form and a plain "Connected" status. It doesn't surface the usage data it already polls (session %, weekly %, reset times) and lacks visual identity. Redesigning the popover to match a polished "Usage for Claude" aesthetic — dark navy palette with coral accents — turns it into a genuinely useful dashboard and makes sign-in more inviting via a dedicated Welcome window.

## What Changes

- **Menu bar popover redesign (not signed in)**: Replace the current sparkles-icon sign-in form with a branded popover showing "Usage for Claude" header, lock icon, "Not Signed In" state, and a prominent coral "Sign In" button.
- **Menu bar popover redesign (authenticated)**: Replace the basic "Connected" view with a full usage dashboard showing current session %, weekly limit %, progress bars, reset countdowns, burn-rate status, and action menu items (Usage History, Launch at Login toggle, Logout).
- **Welcome window**: Clicking "Sign In" in the popover opens a separate centered window with a welcome message, app preview, and two sign-in buttons ("Sign in with Claude Code" functional, "Sign in with Email" placeholder).
- **Claude design tokens**: Extract a `ClaudeTheme` color palette (dark navy, coral, muted text) as a reusable SwiftUI component in the macOS target.
- **Usage data surfacing**: Wire the already-polled `UsageState` (utilization5h, utilization7d, resetAt5h, resetAt7d) into the authenticated popover UI with formatted percentages, progress bars, and relative reset times.

## Capabilities

### New Capabilities
- `macos-menu-bar-ui`: Menu bar popover layout, states (not-signed-in, authenticated dashboard), header, action items, and quit button.
- `welcome-window`: Separate macOS window for onboarding/sign-in with app preview and dual sign-in options.
- `claude-theme`: Reusable design token definitions (colors, spacing) for the Claude visual identity.

### Modified Capabilities
- `macos-usage-writer`: The authenticated view now consumes `UsageState` fields for display (session %, weekly %, reset times) — adds a requirement that the poller exposes a published/observable `UsageState`.

## Impact

- **Files modified**: `SignInView.swift`, `AuthenticatedView.swift`, `TempoMacApp.swift` (macOS target)
- **New files**: `ClaudeTheme.swift`, `WelcomeWindow.swift`, `MenuBarHeaderView.swift`, `UsageDashboardView.swift`, progress bar components
- **No changes to**: OAuth flow, CredentialStore, UsagePoller logic, Shared/ models, iOS target, watchOS target
- **Dependencies**: None new — pure SwiftUI, macOS 14+
