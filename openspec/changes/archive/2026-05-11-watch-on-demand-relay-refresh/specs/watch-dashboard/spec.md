## ADDED Requirements

### Requirement: Dashboard hosts refresh button footer
The dashboard SHALL embed the refresh button described in `watch-refresh-ui` in a centered footer row below the usage ring. The footer SHALL be part of the main dashboard layout, not a floating overlay.

#### Scenario: Footer visible below ring
- **WHEN** the dashboard renders with any state
- **THEN** the refresh button footer is visible below the ring

### Requirement: Dashboard shows freshness indicator inside ring center
The dashboard SHALL display a compact "Updated Xm ago" label inside the ring's center VStack, below the metric labels. The label is driven by `TokenStore.lastRelayReceivedAt`.

#### Scenario: Freshness label positioned inside ring
- **WHEN** the dashboard renders with a known last-relay timestamp
- **THEN** the "Updated Xm ago" label appears inside the ring center below "5H"
