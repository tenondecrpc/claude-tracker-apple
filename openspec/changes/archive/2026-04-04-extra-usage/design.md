## Context

Tempo's macOS menu bar app polls `GET /api/oauth/usage` and displays two utilization gauges (5-hour session and 7-day weekly). The API response already includes an `extra_usage` object with billing data, but the app currently ignores it. The reference app `claude-usage-bar` already implements this feature — we follow its proven pattern (cents-to-dollars conversion, conditional display when enabled, `ExtraUsage` Codable struct).

Current data flow: `UsagePoller.fetchUsage()` → `UsageState` → UI + iCloud write.

## Goals / Non-Goals

**Goals:**
- Parse `extra_usage` from the existing API response
- Display extra usage as `$X.XX / $Y.YY` with a progress bar in the macOS popover, positioned between "Weekly Limit" and burn-rate
- Keep `extraUsage` optional so the app works identically when the field is disabled or absent
- Propagate through iCloud JSON for future iOS/Watch consumption

**Non-Goals:**
- Notifications/alerts for extra usage thresholds (future work)
- iOS or watchOS UI for extra usage (future work)
- Per-model extra usage breakdown

## Decisions

### 1. ExtraUsage as a separate struct on UsageState (not flattened)

Add `var extraUsage: ExtraUsage?` to `UsageState`. This keeps the existing struct backward-compatible (the field is optional and `Codable`) and mirrors the API structure.

**Alternative**: Flatten fields into UsageState directly → rejected because it would add 4 nullable fields to an already-used model and couple billing semantics with utilization semantics.

### 2. Cents stored as Double, converted to dollars on display

Follow `claude-usage-bar`'s pattern: store `usedCredits` and `monthlyLimit` as `Double?` (matching the JSON numeric type), convert to dollars via `/ 100.0` using computed properties, format with `NumberFormatter(.currency, USD)`.

**Alternative**: Store as `Int` cents → rejected because the API sends JSON numbers that may be fractional, and the reference app uses `Double`.

### 3. Conditional UI display

Only show the "Extra Usage" section when `extraUsage?.isEnabled == true`. This matches the reference app's behavior and the screenshot provided.

### 4. UI position: between Weekly Limit and burn-rate

The screenshot shows Extra Usage below Weekly Limit with "Resets monthly" label, followed by the last-polled timestamp. The burn-rate row can be removed or relocated as it's less critical than billing data.

## Risks / Trade-offs

- **[iCloud schema growth]** → Adding `extraUsage` to the iCloud JSON is backward-compatible since `Codable` handles missing keys as `nil`. Old iOS app versions will simply ignore it.
- **[API field absence]** → If `extra_usage` is missing from the response entirely, `JSONDecoder` with optional field handles it gracefully — no crash risk.
