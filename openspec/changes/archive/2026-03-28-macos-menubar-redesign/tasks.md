## 1. Design Tokens

- [x] 1.1 Create `Tempo macOS/ClaudeTheme.swift` with static Color properties (background, surface, accent, textPrimary, textSecondary, progressTrack, destructive, lockIcon)

## 2. Shared Components

- [x] 2.1 Create `UsageProgressBar` custom SwiftUI view (coral fill on dark track, rounded corners, configurable progress 0–1)
- [x] 2.2 Create `MenuBarHeaderView` with "Usage for Claude" title and help/chat icon buttons

## 3. Menu Bar Popover - Not Signed In

- [x] 3.1 Refactor `MacMenuView` to use ClaudeTheme colors and dark color scheme
- [x] 3.2 Replace current `SignInView` with new not-signed-in layout: header, lock icon, "Not Signed In" headline, subtitle, coral "Sign In" button, Quit link
- [x] 3.3 Wire "Sign In" button to open Welcome window via `openWindow(id: "welcome")`

## 4. Welcome Window

- [x] 4.1 Add a SwiftUI `Window("Welcome", id: "welcome")` scene to `TempoMacApp`
- [x] 4.2 Create `WelcomeWindowView` with title, subtitle, preview mockup area, and two sign-in buttons
- [x] 4.3 Wire "Sign in with Claude Code" button to existing OAuth PKCE flow
- [x] 4.4 Style "Sign in with Email" as disabled placeholder with "Coming Soon" indicator
- [x] 4.5 Auto-close Welcome window when `authState.isAuthenticated` becomes true

## 5. Observable Usage State

- [x] 5.1 Add `latestUsage: UsageState?` observable property to `MacAppCoordinator` (or expose from `UsagePoller`)
- [x] 5.2 Update `UsagePoller` to publish latest `UsageState` on each successful poll (in addition to iCloud write)

## 6. Menu Bar Popover - Authenticated Dashboard

- [x] 6.1 Replace current `AuthenticatedView` with usage dashboard: Current Session % with progress bar and reset countdown
- [x] 6.2 Add Weekly Limit section with % progress bar and reset day/time
- [x] 6.3 Add burn-rate status line ("On track" / "High burn" · X%/hr) computed from utilization and reset time
- [x] 6.4 Add last-polled relative timestamp display
- [x] 6.5 Add action menu items: Usage History (placeholder), Launch at Login toggle (placeholder), Logout (functional), Quit

## 7. Polish & Integration

- [x] 7.1 Increase MenuBarExtra frame width from 280 to ~300–320pt if needed for dashboard layout
- [x] 7.2 Apply `.preferredColorScheme(.dark)` to popover and Welcome window
- [x] 7.3 Remove old `SignInView` code-entry view (OAuth code paste) - move to Welcome window flow if still needed
- [x] 7.4 Test full flow: popover → Sign In → Welcome window → OAuth → auto-close → dashboard with live usage data
