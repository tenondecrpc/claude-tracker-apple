## Context

The macOS menu bar app currently has two views: a basic sign-in form (`SignInView`) and a minimal "Connected" status (`AuthenticatedView`). The `UsagePoller` already fetches session and weekly utilization data every 15 minutes, but none of it is surfaced in the UI - it's only written to iCloud for the iOS/watchOS targets. The app uses a single `MenuBarExtra` with `.window` style at 280pt width.

The reference design is the "Usage for Claude" app - a dark navy popover with coral accents showing a full usage dashboard with progress bars, reset countdowns, and action menu items.

## Goals / Non-Goals

**Goals:**
- Redesign the menu bar popover to display real-time usage data (session %, weekly %, reset times, burn rate)
- Apply a Claude-branded dark theme (navy background, coral accents)
- Add a separate Welcome window for the sign-in onboarding flow
- Extract design tokens into a reusable `ClaudeTheme` for consistent styling

**Non-Goals:**
- Usage History feature (listed as menu item but not implemented in this change - button present but non-functional)
- Launch at Login functionality (toggle present in UI but wired up in a future change)
- "Sign in with Email" flow (button present but disabled/placeholder)
- Desktop widget (shown in reference design but out of scope)
- Changes to the OAuth flow, credential storage, or polling logic
- Any changes to iOS or watchOS targets

## Decisions

### 1. Welcome window as a separate SwiftUI `Window` scene

Open a dedicated `Window("Welcome", ...)` scene from the `@main` App struct instead of presenting a sheet from the popover.

**Why**: MenuBarExtra popovers are constrained in size and dismiss on focus loss. A centered 600×500 window allows space for the welcome message, app preview, and sign-in buttons without popover jank.

**Alternative considered**: NSPanel/NSWindow created programmatically - more control but unnecessary complexity for a simple SwiftUI view. Using SwiftUI's `Window` scene is idiomatic macOS 14+.

**Trigger**: `openWindow(id: "welcome")` called from the "Sign In" button in the popover. The `MenuBarExtra` popover dismisses naturally when the window takes focus.

### 2. ClaudeTheme as a static enum with Color extensions

Define `ClaudeTheme` as an `enum ClaudeTheme` (no cases) with static `Color` properties for each design token.

**Why**: Enum with no cases cannot be instantiated - it's a pure namespace. Static properties are simple, discoverable, and work well with SwiftUI color literals.

**Alternative considered**: Asset catalog colors - harder to version-control and review in PRs. Code-defined colors are explicit and diffable.

### 3. Progress bars as custom SwiftUI views

Build `UsageProgressBar` as a custom `View` using `GeometryReader` + `RoundedRectangle` overlay rather than using `ProgressView`.

**Why**: The reference design uses a specific look - coral fill on a dark track with rounded ends. `ProgressView` can't easily be styled to match. A custom view gives full control over gradient, track color, and corner radius.

### 4. Observable UsageState on the coordinator

Expose `UsageState?` as a `@Published` / `@Observable` property on `MacAppCoordinator`, updated by the poller on each successful poll.

**Why**: The poller already has the data. Publishing it on the coordinator (which views already observe) avoids introducing a new observable or changing the data flow. Views can read `coordinator.latestUsage` directly.

### 5. Burn-rate and status computation as view helpers

Calculate "On track" / "High burn" status and the `%/hr` rate as computed properties on a view model or extension, not stored in `UsageState`.

**Why**: These are derived from `utilization5h` and `resetAt5h` - storing them would create stale data and bloat the shared model. Computing on read keeps the model clean.

## Risks / Trade-offs

- **MenuBarExtra width constraint**: The popover is set to 280pt. The authenticated dashboard has more content than the reference (which looks ~320pt wide). → Mitigation: Test at 300pt width; if too cramped, increase frame width to 320.

- **Welcome window lifecycle**: The window could remain open after sign-in completes. → Mitigation: Observe `authState.isAuthenticated` and auto-close the window when it flips to true.

- **Dark appearance forced**: The popover uses a dark theme regardless of system appearance. → Mitigation: Apply `.preferredColorScheme(.dark)` on the popover content and Welcome window. This is intentional - the reference design is always dark.

- **"Sign in with Email" placeholder**: Users might click a disabled button and be confused. → Mitigation: Style it as clearly disabled with "Coming Soon" tooltip or subtitle text.
