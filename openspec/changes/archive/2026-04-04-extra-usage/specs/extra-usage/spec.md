## ADDED Requirements

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

### Requirement: Extra Usage section in macOS menu bar popover
The macOS menu bar popover SHALL display an "Extra Usage" section when `extraUsage?.isEnabled == true`. The section SHALL show:
1. Label "Extra Usage" in secondary text style
2. Dollar amounts formatted as `$X.XX / $Y.YY` in bold title style
3. A `UsageProgressBar` showing `utilization / 100.0` progress
4. Label "Resets monthly" in secondary text style

The section SHALL be positioned after the "Weekly Limit" section.

#### Scenario: Extra usage enabled with active spend
- **WHEN** `extraUsage` has `isEnabled=true`, `usedCredits=0`, `monthlyLimit=2000`
- **THEN** the popover displays "Extra Usage" with "$0.00 / $20.00" and a progress bar at 0%

#### Scenario: Extra usage disabled
- **WHEN** `extraUsage` is `nil` or `isEnabled=false`
- **THEN** no "Extra Usage" section appears in the popover

### Requirement: Extra usage propagated through iCloud
The `UsageState` iCloud JSON payload SHALL include `extraUsage` when present. iOS targets that decode `UsageState` SHALL handle the optional field gracefully.

#### Scenario: iCloud JSON with extra usage
- **WHEN** `UsageState` with `extraUsage` is encoded to JSON and written to iCloud
- **THEN** the JSON includes the `extraUsage` object with all fields
