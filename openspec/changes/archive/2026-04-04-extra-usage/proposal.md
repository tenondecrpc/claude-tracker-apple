## Why

The Anthropic usage API already returns an `extra_usage` object with billing data (enabled status, used credits, monthly limit), but Tempo ignores it entirely. Users who have extra usage enabled need to see their spend ($X.XX / $Y.YY) alongside the existing session and weekly utilization gauges — just like the reference app `claude-usage-bar` already does.

## What Changes

- Parse the `extra_usage` field from the `/api/oauth/usage` API response
- Add an `ExtraUsage` model to represent the billing data (cents-denominated credits, monthly limit, utilization percentage)
- Extend `UsageState` to carry the optional `ExtraUsage` payload
- Display an "Extra Usage" section in the macOS menu bar popover between Weekly Limit and the burn-rate row, showing dollar amounts and a progress bar
- Propagate extra usage data through iCloud sync so iOS/Watch targets can display it in the future

## Capabilities

### New Capabilities
- `extra-usage`: Parsing, modeling, and displaying extra usage billing data from the Anthropic API in the macOS menu bar UI

### Modified Capabilities
- `usage-polling`: The poller's `Response` struct must decode the new `extra_usage` field and pass it through to `UsageState`

## Impact

- **Models**: `Shared/Models.swift` — new `ExtraUsage` struct, `UsageState` gains optional `extraUsage` property
- **API parsing**: `Tempo macOS/UsagePoller.swift` — extend `Response` Decodable struct
- **UI**: `Tempo macOS/AuthenticatedView.swift` — new "Extra Usage" section with dollar formatting and progress bar
- **iCloud**: The iCloud JSON payload grows to include extra usage; iOS reader must handle the optional field gracefully
- **No breaking changes** — `extraUsage` is optional throughout
