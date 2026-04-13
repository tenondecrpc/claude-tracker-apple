## 1. Data Model

- [x] 1.1 Add `ExtraUsage` struct to `Shared/Models.swift` with `isEnabled`, `usedCredits`, `monthlyLimit`, `utilization` fields, `CodingKeys`, computed dollar properties, and `formatUSD()` static method
- [x] 1.2 Add optional `extraUsage: ExtraUsage?` property to `UsageState`
- [x] 1.3 Update `UsageState.mock` to include a sample `extraUsage` value

## 2. API Parsing

- [x] 2.1 Add `ExtraUsage?` to the `Response` struct in `UsagePoller.fetchUsage()` and pass it through to the returned `UsageState`
- [x] 2.2 Add `ExtraUsage?` to the iOS `UsageStatePoller.fetchUsage()` `Response` struct (if applicable)

## 3. macOS Menu Bar UI

- [x] 3.1 Add "Extra Usage" section to `AuthenticatedMenuView.usageContent()` - show label, dollar amounts (`$X.XX / $Y.YY`), progress bar, and "Resets monthly" text, conditionally displayed when `extraUsage?.isEnabled == true`
- [x] 3.2 Reposition burn-rate and last-polled rows after the Extra Usage section

## 4. Verification

- [x] 4.1 Build the macOS target in Xcode and verify no compile errors
