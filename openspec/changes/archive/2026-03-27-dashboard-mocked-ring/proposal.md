## Why

The watch app is a blank template - there is no UI for the user to glance at. Implementing the dashboard with a mocked usage ring unblocks all further watchOS development by establishing the UI layer before real data (OAuth API, WatchConnectivity) is wired in.

## What Changes

- Add `TokenStore.swift` - `@Observable` data store with `UsageState` (mocked) and a `sessions` history array
- Add `UsageState` struct with `utilization5h`, `utilization7d`, `resetAt5h`, `resetAt7d`, and `isMocked` flag
- Replace blank `ContentView.swift` (Watch target) with a dashboard showing:
  - A circular usage ring driven by `usageState.utilization5h`
  - A `⚠ mock` badge visible while `isMocked == true`
  - A reset countdown ("2hr 13min left") derived from `resetAt5h`
  - A secondary 7-day utilization indicator
- Add `CompletionView.swift` - full-screen sheet triggered by `pendingCompletion` (stubbed for now)

## Capabilities

### New Capabilities

- `watch-dashboard`: Main watchOS dashboard - usage ring, mock badge, reset countdown, session sheet trigger
- `token-store`: Observable data store for usage state and session history, with mock data support

### Modified Capabilities

<!-- No existing specs - this is the first implementation phase -->

## Impact

- `Tempo Watch Extension/ContentView.swift` - replaced entirely
- `Tempo Watch Extension/` - two new Swift files added (`TokenStore.swift`, `CompletionView.swift`)
- No iOS target changes; no backend/hook changes
- No external dependencies added
