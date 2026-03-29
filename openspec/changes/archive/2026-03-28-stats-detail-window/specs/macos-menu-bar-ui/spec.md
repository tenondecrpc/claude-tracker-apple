## MODIFIED Requirements

### Requirement: Authenticated popover has action menu items
Below the usage data, after a divider, the popover SHALL show:
- "Usage History" with a chart.line.uptrend icon that opens the stats detail window via `openWindow(id: "stats-detail")`
- "Launch at Login" with a power icon and a toggle switch (non-functional placeholder)
- "Logout" with an arrow.right.square icon that triggers sign-out
- "Quit" text in coral at the bottom

#### Scenario: Usage History opens stats window
- **WHEN** the user clicks "Usage History" in the authenticated popover
- **THEN** the stats detail window opens (or comes to front if already open)

#### Scenario: Logout clears auth and returns to sign-in state
- **WHEN** the user clicks "Logout"
- **THEN** credentials are cleared and the popover switches to the not-signed-in state

#### Scenario: Quit terminates the app
- **WHEN** the user clicks "Quit"
- **THEN** the macOS app terminates
