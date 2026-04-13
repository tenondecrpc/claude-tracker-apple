## MODIFIED Requirements

### Requirement: Popover header with title and action icons
The menu bar popover SHALL display a header row containing "Tempo" as a bold title on the left, a service status dot (8pt circle, color per `ServiceHealthState`), and a refresh icon button on the right. The help (questionmark.circle) and chat (message) icon buttons SHALL be removed. A horizontal divider SHALL separate the header from the content below.

#### Scenario: Header displayed in all states
- **WHEN** the menu bar popover is opened
- **THEN** the header row with "Tempo" title, a status dot, and refresh icon is visible at the top

### Requirement: Not-signed-in state shows lock and sign-in button
When the user is not authenticated, the popover SHALL display a centered lock icon using `TempoTheme.info` color (`lock.fill`), "Not Signed In" as a bold headline, a subtitle "Sign in to view your usage", and a full-width violet (`TempoTheme.accent`) "Sign In" button. A "Quit" text button in `TempoTheme.critical` SHALL appear at the bottom below a divider.

#### Scenario: Unauthenticated popover appearance
- **WHEN** the popover opens and the user is not authenticated
- **THEN** the lock icon, "Not Signed In" headline, subtitle, violet "Sign In" button, and "Quit" link are displayed

#### Scenario: Sign In button opens Welcome window
- **WHEN** the user clicks the "Sign In" button
- **THEN** the Welcome window opens as a separate centered macOS window

### Requirement: Menu bar percentage text visibility follows user preference
The menu bar item SHALL respect the Show Percentage in Menu Bar preference for authenticated usage display.

#### Scenario: Percentage text is shown
- **WHEN** the user has Show Percentage in Menu Bar enabled and usage data is available
- **THEN** the menu bar item displays the numeric session percentage next to the pulse dot icon

#### Scenario: Percentage text is hidden
- **WHEN** the user disables Show Percentage in Menu Bar
- **THEN** the menu bar item displays the pulse dot icon only with no percentage text

### Requirement: Authenticated state shows ring dashboard
When the user is authenticated and usage data is available, the popover SHALL display the ring gauge dashboard as defined in the `popover-ring-dashboard` spec. The previous flat VStack layout with `UsageProgressBar` blocks for session, weekly, and extra usage SHALL be replaced entirely.

#### Scenario: Ring dashboard renders with live data
- **WHEN** the poller reports `utilization5h = 0.42` and `utilization7d = 0.18`
- **THEN** the popover shows concentric rings at 42% (inner, violet) and 18% (outer, blue), center label "42", session chip "42% · Xh Ym", weekly chip "18%"

#### Scenario: Last polled timestamp shown
- **WHEN** the last successful poll was 2 minutes ago
- **THEN** the popover shows "2 min ago" as the last-polled time (in `.footnote` in `TempoTheme.textSecondary`)

### Requirement: Promo indicator is shown only when double-limit promotion is active
When usage payload decoding indicates an active double-limit promotion, the authenticated popover SHALL show a `2x promo active` indicator above the ring gauge, right-aligned, using `TempoTheme.warning` accent color.

#### Scenario: Promotion active
- **WHEN** `isDoubleLimitPromoActive` is `true` in the latest usage state
- **THEN** the popover shows `2x promo active` above the ring gauge, right-aligned

#### Scenario: Promotion inactive or unknown
- **WHEN** `isDoubleLimitPromoActive` is `false` or `nil`
- **THEN** the promo indicator is not shown

### Requirement: Authenticated popover has action menu items
Below the burn rate card, after a divider, the popover SHALL show:
- "Usage History" button that opens the stats detail window
- "Logout" button (with account email in `.footnote` below)
- A divider
- "Quit" text in `TempoTheme.critical` at the bottom

#### Scenario: Usage history opens stats detail
- **WHEN** the user clicks "Usage History"
- **THEN** the stats detail window opens

#### Scenario: Logout clears auth and returns to sign-in state
- **WHEN** the user clicks "Logout"
- **THEN** credentials/session state are cleared and the popover switches to the not-signed-in state

#### Scenario: Quit terminates the app
- **WHEN** the user clicks "Quit"
- **THEN** the macOS app terminates

### Requirement: Logout stops session and blocks auto-restore
When the user clicks "Logout", the app SHALL:
1. Reset `authState.isAuthenticated` and `authState.isAwaitingCode` to `false`
2. Set `authState.requiresExplicitSignIn = true` to block automatic session restoration
3. Stop the usage poller
4. Transition the popover immediately to the not-signed-in state

Credentials on disk are NOT deleted. No confirmation dialog is required.

#### Scenario: Poller stops on logout
- **WHEN** the user clicks "Logout"
- **THEN** the 30-minute usage polling timer is cancelled and no further API requests are made

#### Scenario: Popover switches to not-signed-in immediately
- **WHEN** the user clicks "Logout"
- **THEN** the popover transitions to the not-signed-in state without app restart

#### Scenario: Reopening menu bar after logout stays signed out
- **WHEN** the user clicks "Logout" and then reopens the menu bar popover
- **THEN** the popover shows "Not Signed In" - no auto-restore occurs even if credentials exist on disk

#### Scenario: Credentials reusable via explicit sign-in
- **WHEN** the user clicks "Sign in with Claude Code" after a logout
- **THEN** `requiresExplicitSignIn` is reset to `false`, the app checks stored credentials, and restores the session without opening the browser

### Requirement: Dark theme applied to popover
The popover content SHALL use a dark color scheme (`.preferredColorScheme(.dark)`) with `TempoTheme` colors for background, text, and accents. `TempoTheme.background` (#19191C) SHALL be the popover window background.

#### Scenario: Popover uses dark appearance
- **WHEN** the popover opens regardless of system appearance setting
- **THEN** the popover renders with dark charcoal background (#19191C) and light text
