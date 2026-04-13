## MODIFIED Requirements

### Requirement: ExtraUsage data model
The system SHALL define an `ExtraUsage` struct that is `Codable` with the following fields:
- `isEnabled: Bool` - whether extra usage billing is active
- `usedCredits: Double?` - credits consumed this month, in cents
- `monthlyLimit: Double?` - maximum monthly spend, in cents
- `utilization: Double?` - percentage of limit used (0–100)

The struct SHALL provide computed properties:
- `usedCreditsAmount: Double?` - `usedCredits / 100.0` (dollars)
- `monthlyLimitAmount: Double?` - `monthlyLimit / 100.0` (dollars)
- `formatUSD(_:) -> String` - static method formatting a dollar amount as `$X.XX`

#### Scenario: Decoding enabled extra usage from JSON
- **WHEN** the API returns `{"is_enabled": true, "monthly_limit": 2000, "used_credits": 530, "utilization": 26.5}`
- **THEN** `ExtraUsage` decodes with `isEnabled=true`, `usedCreditsAmount=5.30`, `monthlyLimitAmount=20.00`, `utilization=26.5`

#### Scenario: Decoding disabled extra usage from JSON
- **WHEN** the API returns `{"is_enabled": false, "monthly_limit": null, "used_credits": null, "utilization": null}`
- **THEN** `ExtraUsage` decodes with `isEnabled=false` and all optional fields `nil`

### Requirement: UsageState carries optional ExtraUsage
`UsageState` SHALL have an optional `extraUsage: ExtraUsage?` property. When the API does not include `extra_usage`, this field SHALL be `nil`.

#### Scenario: UsageState without extra usage
- **WHEN** `UsageState` is decoded from JSON that lacks an `extraUsage` key
- **THEN** `extraUsage` is `nil` and all other fields remain valid

### Requirement: Extra Usage displayed in popover as collapsed disclosure in burn rate card
When `extraUsage?.isEnabled == true`, the macOS menu bar popover SHALL display Extra Usage as a `DisclosureGroup` collapsed by default inside the burn rate card. The disclosure SHALL show:
- Label "Extra Usage" as the disclosure group title in `.footnote` in `TempoTheme.textSecondary`
- When expanded: dollar amounts `$X.XX / $Y.YY` in `.callout.monospacedDigit()` and a thin linear progress bar in `TempoTheme.info`

The Extra Usage section SHALL NOT appear as a standalone progress bar block in the popover body. When `extraUsage?.isEnabled == false` or `extraUsage` is `nil`, the disclosure group SHALL NOT appear.

#### Scenario: Extra usage enabled - disclosure visible but collapsed
- **WHEN** `extraUsage` has `isEnabled=true` and `usedCredits=530`, `monthlyLimit=2000`
- **THEN** the burn rate card shows a collapsed "Extra Usage" disclosure group

#### Scenario: Extra usage enabled - disclosure expanded
- **WHEN** the user taps the "Extra Usage" disclosure group
- **THEN** it expands to show "$5.30 / $20.00" and a 26.5% progress bar in sky blue

#### Scenario: Extra usage disabled
- **WHEN** `extraUsage` is `nil` or `isEnabled=false`
- **THEN** no Extra Usage disclosure appears in the burn rate card

### Requirement: Extra Usage card in detail window Overview tab
The detail window Overview tab SHALL display an Extra Usage card in the 2-column card grid when `extraUsage?.isEnabled == true`. The card SHALL show:
- Section header: "Extra Usage" in `TempoTheme.textSecondary` `.footnote.weight(.semibold)`
- Dollar amounts: `$X.XX / $Y.YY` in `.title3.bold().monospacedDigit()`
- A horizontal progress bar in `TempoTheme.info` at `utilization / 100.0` progress
- "Resets monthly" caption in `TempoTheme.textSecondary` `.footnote`
- Left-edge 4pt accent stripe in `TempoTheme.info`

When `extraUsage?.isEnabled == false` or `nil`, no Extra Usage card SHALL appear in the grid.

#### Scenario: Extra usage card visible in overview when enabled
- **WHEN** `extraUsage?.isEnabled == true` and the Overview tab is selected
- **THEN** the Extra Usage card appears in the 2-column card grid

#### Scenario: Extra usage card absent when disabled
- **WHEN** `extraUsage?.isEnabled == false` and the Overview tab is selected
- **THEN** no Extra Usage card appears in the card grid

### Requirement: Extra usage propagated through iCloud
The `UsageState` iCloud JSON payload SHALL include `extraUsage` when present. iOS targets that decode `UsageState` SHALL handle the optional field gracefully.

#### Scenario: iCloud JSON with extra usage
- **WHEN** `UsageState` with `extraUsage` is encoded to JSON and written to iCloud
- **THEN** the JSON includes the `extraUsage` object with all fields
