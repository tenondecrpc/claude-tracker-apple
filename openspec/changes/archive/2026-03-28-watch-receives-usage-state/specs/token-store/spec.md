## ADDED Requirements

### Requirement: TokenStore.apply sets usageState from incoming payload
`TokenStore` SHALL expose `func apply(_ state: UsageState)`. It SHALL set `usageState = state`. Because `usageState` is `private(set)`, `apply` SHALL be the only external mutation path for this property.

#### Scenario: Apply called with real data
- **WHEN** `store.apply(UsageState(utilization5h: 0.6, ..., isMocked: false))` is called
- **THEN** `store.usageState.utilization5h` is `0.6` and `store.usageState.isMocked` is `false`

#### Scenario: Mock badge disappears after apply
- **WHEN** `store.apply` is called with a `UsageState` where `isMocked` is `false`
- **THEN** any observer of `store.usageState.isMocked` sees `false` (mock badge hides automatically)

#### Scenario: Apply is the only mutation path
- **WHEN** external code attempts to assign `store.usageState = someState` directly
- **THEN** the compiler rejects the assignment (private(set) enforcement)
