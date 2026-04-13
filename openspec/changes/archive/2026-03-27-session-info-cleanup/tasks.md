## 1. Model Update

- [x] 1.1 Remove `limitResetAt: Date?` from `SessionInfo` in `Shared/Models.swift`
- [x] 1.2 Remove `isDoubleLimitActive: Bool` from `SessionInfo` in `Shared/Models.swift`

## 2. Fixture Update

- [x] 2.1 Update all `SessionInfo` initializers in `MockData.swift` to remove the two deleted arguments
- [x] 2.2 Verify `costUSD` is `0.0` in all mock fixtures

## 3. Verification

- [x] 3.1 Build the project - confirm zero compiler errors across all targets (Shared, iOS, Watch Extension)
