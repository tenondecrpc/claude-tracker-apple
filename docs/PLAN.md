# TempoForClaude - Roadmap and Backlog

This is the single planning document for the project.

- Use the phased sections below for committed implementation work.
- Use the backlog section at the end for unscheduled or exploratory ideas.
- When a backlog item becomes committed work, move it into the relevant phase and remove it from the backlog to avoid duplication.

**Architecture**: Two complementary data sources feed the watch:

1. **Stop hook pipeline** (session events): Claude Code Stop hook → iCloud Drive JSON → iOS companion → WatchConnectivity → watchOS haptic + session sheet
2. **OAuth API** (utilization ring): macOS menu bar app polls `GET /api/oauth/usage` → iCloud Drive → iOS reads via `NSMetadataQuery` → WatchConnectivity → watchOS usage ring

The hook alone cannot provide utilization % or reset timestamps - those require OAuth because the plan limit (5h/7d token ceiling) is account-specific and never exposed locally.

---

## Data Sources

Three distinct data sources - each with a different role. None replaces the others.

| Source | Mechanism | What it provides | What it cannot provide |
|---|---|---|---|
| **Stop hook** | Event-driven (fires at session end) | Per-session tokens, cost, duration - at the exact moment the session closes | Utilization %, plan limits, reset timestamps |
| **Claude Code local DB** (`~/.claude/`) | Polling / file watch | Full session history: 209 sessions, streaks, totals, model breakdown - same data `/stats` shows in the CLI | Real-time event trigger; plan limits |
| **Anthropic OAuth API** | Polling (15 min) | `utilization5h`, `utilization7d`, `resetAt5h`, `resetAt7d` - relative to your specific plan limit | Per-session token counts; context window data |

### Why the hook cannot be replaced by the local DB

`/stats` and the local DB contain the same historical data the hook would capture. The critical difference is **event delivery**: the hook fires the instant a session ends, enabling an immediate haptic on the watch. Reading the local DB requires polling - you'd have to guess when to check, and you'd still need to diff against the previous state to detect a new session.

### Why the local DB matters for Phase 8

The local DB (`~/.claude/`) already contains the full session history (209 sessions, activity grid, model breakdown). Phase 8 (`StatsView`) can read this directly instead of building a custom history store from scratch via hooks. Confirm the exact file path and schema in Phase 0.

---

## iCloud Transport - Options

The macOS → iOS relay uses iCloud Drive as the channel. The "iCloud Documents" entitlement **requires a paid Apple Developer account ($99/year)**. With a free Personal Team, writing from macOS works (direct path), but reading from iOS via `NSMetadataQuery` is blocked.

### Current Status (2026-03-28)
- ✅ macOS writes `usage.json` to `~/Library/Mobile Documents/com~apple~CloudDocs/Tempo/` without entitlement
- ⚠️ iOS cannot read via `NSMetadataQuery` without iCloud entitlement - static "Connect via Mac app" screen
- ✅ All code is implemented and ready - only needs entitlement activation

### Option A - Apple Developer Account ($99/year) ⭐ recommended
Enables iCloud Documents on both targets (macOS + iOS) using the same container ID. Current code works without changes. Also unlocks Push Notifications and App Store distribution.

### Option B - Cloudflare Workers KV (free)
Replace `UsagePoller.writeToiCloud()` and `iCloudUsageReader` with HTTP PUT/GET to a free KV store. Requires:
- Cloudflare account (free)
- Worker with authenticated endpoint (shared token in `credentials.json`)
- Refactor `UsagePoller.swift` (write) and `iCloudUsageReader.swift` (read → HTTP polling every 60s)
- No Apple entitlements required

### Option C - Defer iOS sync (current situation)
macOS app works standalone: OAuth, polling, data visible in menu bar. iOS shows static "Connect via Mac app" screen without syncing. Watch has no real data. Acceptable as v0 while deciding on transport.

---

## Execution Order

```
TRACK A - Usage ring (OAuth):     0 → 1 → 2
TRACK B - Session haptics (hook): 0 → 3 → 4 → 5

THEN:  6 (reset alarm) → 7 (QA) → 8 (stats) → 9 (context window)
```

**Track A and Track B share Phase 0. Run A before B - the watch infrastructure built in Phase 2 (WatchConnectivity + TokenStore updates) is reused by Track B.**

---

## Phase 0: Documentation Discovery
**TIER 1 - Prerequisite for everything**

**Goal**: Verify exact APIs before writing any code. Deploy research subagents on:

1. **Anthropic OAuth API** - exact endpoints, PKCE flow, token refresh, rate limits
   - Need: endpoint URL for usage data, response shape (`five_hour.utilization`, `five_hour.resets_at`, etc.), OAuth scopes required
   - Source: WebFetch the Anthropic OAuth docs / inspect claude.ai network requests

2. **Claude Code hooks** - exact env vars the Stop hook receives
   - Need: `input_tokens`, `output_tokens`, `cost_usd`, session ID, any limit/reset data, context window stats
   - Source: WebFetch the Claude Code hooks docs

3. **Claude Code local DB** - schema and file path of the session history database
   - `/stats` command reads this; same data available to us directly
   - Need: exact file path (`~/.claude/` - confirm subdirectory), format (SQLite? JSON?), session record schema
   - Relevant for Phase 8 (StatsView) - avoids building a redundant history store

4. **WatchConnectivity** - `WCSession`, `sendMessage` vs `transferUserInfo`, activation states, background delivery
   - Source: Apple Developer docs + `.agents/skills/swiftui-expert-skill/references/`

5. **NSMetadataQuery for iCloud** - watching file changes in `~/Library/Mobile Documents/com~apple~CloudDocs/`
   - Pattern: `NSMetadataQuery` with `NSMetadataQueryUbiquitousDocumentsScope`

6. **WKHapticType (watchOS)** - enum cases: `.notification`, `.directionUp`, `.success`, etc.
   - Also: `WKInterfaceDevice.current().play(_:)`

7. **Local notifications on watchOS** - `UNUserNotificationCenter` for the reset alarm

**Output**: `/docs/APIS.md` with confirmed API signatures before any code is written.

---

## Phase 1: macOS OAuth - Real Utilization Data
**TIER 1 - Track A / Makes the usage ring real**

**Goal**: macOS menu bar app authenticates with Anthropic, polls usage, writes `UsageState` to iCloud Drive. iOS reads via `NSMetadataQuery` and relays to watch. Mock badge disappears.

**Architecture (macOS-first, per `macos-oauth-desktop` change):**

```
macOS menu bar app
  └─ MacOSAPIClient (OAuth PKCE, browser + paste-code)
  └─ CredentialStore (~/.config/tempo-for-claude/credentials.json, 0600 perms)
  └─ UsagePoller (15-min poll → UsageState → iCloud Drive)
      └─ ~/Library/Mobile Documents/.../Tempo/usage.json

iOS companion (no sign-in required)
  └─ iCloudUsageReader (NSMetadataQuery → decode UsageState)
  └─ WatchRelayManager (transferUserInfo → watchOS)

watchOS → TokenStore → usage ring
```

**What to implement:** ✅ Complete (`macos-oauth-desktop` change implemented)

1. **`Tempo macOS/`** - new macOS target (SwiftUI MenuBarExtra, `LSUIElement = YES`)
   - ✅ `CredentialStore.swift` - file-based token storage (`0600`/`0700` perms)
   - ✅ `MacOSAPIClient.swift` - OAuth PKCE, `NSWorkspace.shared.open()`, auto-restore, token refresh, sign-out
   - ✅ `UsagePoller.swift` - 15-min poll, exponential backoff on 429, iCloud write
   - ✅ `TempoMacApp.swift` - `@main` App with `MenuBarExtra`
   - ✅ `SignInView.swift` / `AuthenticatedView.swift` - minimal menu bar UI

2. **iOS changes**:
   - ✅ `iCloudUsageReader.swift` - `NSMetadataQuery` watching `usage.json`, download handling, restart on foreground
   - ✅ `ContentView.swift` - "Connect via Mac app" / "Syncing from Mac" / staleness indicator

**Remaining manual setup (Xcode):**
- Add macOS app target "Tempo macOS" to `Tempo.xcodeproj` (`LSUIElement = YES`)
- Link `Shared/` folder to macOS target via `PBXFileSystemSynchronizedRootGroup`
- Enable iCloud capability with "iCloud Documents" on both macOS and iOS targets (same container ID)

**Anti-pattern guards:**
- Do NOT store OAuth tokens in `UserDefaults` or iCloud
- Do NOT poll more than every 15 minutes
- Do NOT reuse Claude Code's own OAuth tokens (they are not exposed in a reusable format)

---

## Phase 2: watchOS Receives UsageState - Ring Goes Live
**TIER 1 - Track A / Watch shows real data for the first time**

**Goal**: Watch receives `UsageState` from iOS, updates `TokenStore`, ring shows real utilization %, mock badge disappears.

**What to implement:** ✅ Complete

1. **`WatchSessionReceiver.swift`** (Watch Extension) - `WCSessionDelegate`:
   - ✅ `session(_:didReceiveUserInfo:)` → decode payload type (UsageState vs SessionInfo)
   - ✅ On `UsageState`: update `TokenStore.usageState`, set `isMocked = false`

2. **`TokenStore` update** - ✅ `func apply(_ state: UsageState)`:
   - ✅ Sets `usageState = state`
   - ✅ Called by `WatchSessionReceiver`

3. **Wire receiver to app entry point** - ✅ `WatchSessionReceiver` activated on watch app launch

**Verification checklist:**
- Run Phase 1 iOS → watch simulator shows real % (not 42%)
- Mock badge disappears from watch face
- Countdown shows correct real reset time

---

## Phase 3: Stop Hook - Session Events on Mac
**TIER 1 - Track B / Captures per-session data**

**Goal**: Every time a Claude Code session ends, a JSON file lands in iCloud with tokens, cost, and session ID.

**What to implement:**

1. **`SessionInfo`** (already in `Shared/Models.swift`) - verify fields match hook env vars confirmed in Phase 0

2. **Stop hook shell script** at `~/.claude/hooks/stop-tracker.sh`:
   - Reads env vars from Claude Code (exact names from Phase 0)
   - Writes JSON to `~/Library/Mobile Documents/com~apple~CloudDocs/Tempo/latest.json`
   - Creates directory if missing
   - `chmod +x` required

3. **Register the hook** in `~/.claude/settings.json`:
   ```json
   { "hooks": { "Stop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/stop-tracker.sh" }] }] } }
   ```

**Verification checklist:**
- Run `echo $CLAUDE_INPUT_TOKENS` inside a test hook to confirm var names
- End a real Claude Code session → check `latest.json` appears in iCloud folder
- Validate JSON parses into `SessionInfo`

---

## Phase 4: iOS iCloud Monitor → Relay SessionInfo to Watch
**TIER 1 - Track B / Bridge between Mac and Watch**

**Goal**: iOS detects new `latest.json` in iCloud and forwards `SessionInfo` to the watch via `WatchRelayManager`.

**What to implement:** ✅ Complete

1. **`iCloudUsageReader.swift`** (iOS target):
   - ✅ `NSMetadataQuery` watching `latest.json`
   - ✅ On change → decode `SessionInfo` → call `WatchRelayManager.sendSession(_:)`

2. **`WatchRelayManager` update** - ✅ `sendSession(_ session: SessionInfo)`:
   - ✅ Encodes `SessionInfo` as `[String: Any]` with type discriminator `"type": "session"`
   - ✅ Uses `transferUserInfo(_:)` (reliable background delivery)

3. **Wire to iOS app launch** - ✅ `iCloudUsageReader.start()` alongside the poller

**Files:**
```
Tempo/
├── iCloudUsageReader.swift   ← monitors latest.json, triggers relay
└── WatchRelayManager.swift  ← sendSession implemented
```

**Verification checklist:**
- Drop a valid `latest.json` into the iCloud folder manually → `iCloudUsageReader` fires
- Confirm `WCSession` delivers `userInfo` to watch simulator with `"type": "SessionInfo"`

---

## Phase 5: watchOS Session Receive - Haptic + CompletionView
**TIER 1 - Track B / The haptic magic**

**Goal**: Watch receives `SessionInfo`, plays haptic, presents `CompletionView`.

**What to implement:** ✅ Complete

1. **`WatchSessionReceiver` update** (from Phase 2):
   - ✅ On `SessionInfo` payload: play haptic + set `TokenStore.pendingCompletion`
   - ✅ `WKInterfaceDevice.current().play(.notification)`

2. **`TokenStore` update** - `pendingCompletion` already exists; confirmed set from the receiver

3. **`WatchAlertManager`** - handles notification presentation on session complete

4. **`CompletionView.swift`** - shows session details (tokens, cost, duration)

**Verification checklist:**
- End a real Claude Code session → watch vibrates + `CompletionView` appears with correct tokens + cost
- Dismiss sheet → `pendingCompletion` clears
- Subsequent session → sheet reappears correctly

---

## Phase 6: Limit Reset Alarm
**TIER 2 - Most-requested feature**

**Goal**: Watch fires a strong haptic + notification at the exact moment the 5h limit resets.

**`ResetAlarmManager.swift`** (Watch Extension):
- `UNUserNotificationCenter` - schedule notification at `TokenStore.usageState.resetAt5h`
- On trigger: `WKInterfaceDevice.current().play(.notification)`
- Reschedules automatically when `usageState` updates (i.e. every 15-min OAuth poll)

**Note**: This phase is trivially correct only after Phase 1–2, because `resetAt5h` is a real timestamp from the OAuth API.

**Verification checklist:**
- Schedule alarm 30 seconds in the future → notification fires + haptic plays
- Update `usageState` with new reset time → alarm reschedules

---

## Phase 7: Final Verification & QA
**TIER 2 - Before declaring MVP done**

**End-to-end test sequence:**
1. Fresh install → OAuth sign-in → watch shows real ring
2. End a Claude Code session → hook fires → JSON in iCloud → iOS relays → watch shows haptic + `CompletionView`
3. Wait for limit reset → alarm fires on watch at correct time

**Code health checklist:**
- Grep for deprecated APIs: `foregroundColor`, `NavigationView`, `ObservableObject`
- Verify `@State` is always `private`
- Verify no `sendMessage` (use `transferUserInfo` for reliability)
- Verify hook script has `chmod +x`
- Verify `Shared/Models.swift` is correctly linked to all targets

---

## Phase 8: Stats Dashboard + Complications
**TIER 2 - Visibility & glanceability**

**Data source for history**: Claude Code already stores full session history in `~/.claude/` (the same data `/stats` shows in the CLI - 209 sessions, activity grid, model breakdown). Read this directly instead of building a redundant history store from Stop hook events. Schema confirmed in Phase 0.

**What to implement:**

1. **`StatsView.swift`** - scrollable list of past sessions with token bars

2. **`TokenComplication.swift`** - Watch face complication:
   - Graphic corner: usage % + countdown to reset
   - Circular: usage percentage
   - Uses `WidgetKit` (watchOS supported families)

3. **`ComplicationProvider.swift`** - `TimelineProvider` reading from App Group `UserDefaults`

**Anti-pattern guards:**
- Complications require App Group entitlement - set up in Xcode first
- Complication timeline needs updates every ~15 min for accurate countdown

---

## Phase 9: Context Window Tracking
**TIER 3 - High-value addition**

**Goal**: Show context window fullness on the watch with haptic alerts at thresholds.

**Data source**: Claude Code hooks (Stop hook env vars - confirm exact names in Phase 0).

**What the data looks like:**
```
Total:        50k / 200k tokens (25%)
  System prompt:      6.3k  (3.1%)
  System tools:       7.6k  (3.8%)
  Memory files:         205  (0.1%)
  Skills:             1.2k  (0.6%)
  Messages:          35.4k (17.7%)
  Free space:         116k (58.2%)
```

**What to implement:**

1. **`ContextState.swift`** (Shared):
   ```swift
   struct ContextState: Codable {
       var totalTokens: Int
       var maxTokens: Int
       var utilization: Double     // 0.0–1.0
       var breakdown: ContextBreakdown
       var timestamp: Date
   }

   struct ContextBreakdown: Codable {
       var systemPrompt: Int
       var systemTools: Int
       var memoryFiles: Int
       var skills: Int
       var messages: Int
       var autocompactBuffer: Int
   }
   ```

2. **Stop hook extension** - extend `stop-tracker.sh` to also write `context.json` to iCloud

3. **iOS companion update** - `iCloudUsageReader` watches `context.json`, relays `ContextState` via `WatchRelayManager`

4. **watchOS dashboard update** - `TokenStore` gains `contextState: ContextState?`; `ContentView` shows context gauge

5. **Threshold alerts** - configurable (default: warn 70%, critical 90%):
   - Fire only on upward threshold crossing, not on every hook call
   - Discard context data older than 10 minutes

---

## Future: Windows / Cross-Platform Support
**Out of scope for now**

The current architecture uses iCloud as the transport layer (Mac-only). To support Windows, replace iCloud with an HTTP relay:

```
Stop hook (any OS) → curl POST to relay → iOS app (polling/WebSocket) → WatchConnectivity → watch
```

**Relay options:** ntfy.sh (zero backend), Supabase Realtime (free tier), Cloudflare Worker + KV

**What changes:** `stop-tracker.sh` + `iCloudUsageReader.swift`
**What does NOT change:** `SessionInfo` model, WatchConnectivity relay, all watchOS code.

---

## Reference Apps

### Usage for Claude (Amir Hayek)
macOS menu bar + iOS companion app. Requires sign-in to Claude account via OAuth. Fetches utilization data from the Anthropic OAuth API, saves locally, and syncs to iCloud for the iOS companion. The iCloud sync is a cache - the authoritative data source is always the API.

### claude-usage-bar (Blimp-Labs)

**Repo**: https://github.com/Blimp-Labs/claude-usage-bar

**What it is**: macOS menu bar app showing real-time Claude API utilization via the Anthropic OAuth API.

### How the OAuth API works

- **Auth**: OAuth via browser - no manual API keys. User signs in with their Claude account, gets a token, app uses it to query Anthropic's usage endpoints.
- **Endpoints**: Same internal endpoints that claude.ai uses to show usage on the web settings page. Not part of the public Anthropic API.
- **Polling**: Every 60 seconds (claude-usage-bar) / 15 minutes (our target).
- **Data**: 5-hour session utilization %, 7-day weekly limit %, reset countdowns.

### Real-World Accuracy Comparison (2026-03-27)

| Source | 5h Usage | 7d Usage | Freshness |
|---|---|---|---|
| **claude.ai web** (ground truth) | 79% | 33% | "just now" |
| **claude-usage-bar** (OAuth API) | 79% | 33% | "2 min, 21 sec ago" |
| **Usage for Claude** (OAuth API, same mechanism) | 24% | 29% | "1 hour ago" |

**Takeaway**: Both OAuth-based apps query the same Anthropic endpoints. "Usage for Claude" showed stale data (1 hour behind) - likely a polling interval or caching issue in that app, not a fundamental limitation of the OAuth approach. Both approaches are superior to any hook-based estimation for utilization data.

### Key Patterns Worth Adopting

1. **OAuth API as authoritative source** - matches claude.ai exactly; hook data cannot compute utilization %
2. **Reset timestamp reconciliation** - preserve previous value if server omits it; detect rollover when utilization drops
3. **Threshold-crossing detection** - fire only on upward transition, avoid alert fatigue
4. **Exponential backoff on 429** - smart rate-limit handling
5. **7-day window + extra usage** - track both free and paid credits
6. **Per-model breakdown** - Opus vs Sonnet utilization (future)

### Implication for Tempo

- **OAuth API** (Phases 1–2) → authoritative utilization % and reset timestamps for the usage ring
- **Stop hook** (Phases 3–5) → unique value: real-time haptic on session completion + per-session token/cost breakdown that no polling-based app can match

---

## Unscheduled Backlog
**Future-facing ideas that are explicitly not part of the committed phase plan yet**

1. **Multi-account support** - Add and switch between multiple Claude accounts within one app instance.
2. **Light mode** - Support a full light-theme variant instead of dark-mode-only UI.
3. **Pace prediction** - Forecast session and weekly usage based on burn rate and historical behavior.
4. **Live session chart** - Show real-time, sub-30-second chart updates during an active session.
5. **Day/week usage breakdowns** - Add weekday and time-of-day breakdowns, heatmaps, or similar granular views.
6. **Bar charts** - Offer bar-chart alternatives alongside the current line/area visualizations.
7. **Consumption rate histogram** - Show how often usage falls into utilization bands such as 0–25% or 25–50%.
8. **Scheduled triggers / automations** - Add configurable automation rules such as “alert me at 80%” or Shortcuts integration.
9. **Codex / Claude API key support** - Support usage tracking for users working through raw API keys instead of OAuth.
10. **All Accounts dashboard** - Aggregate usage across multiple Claude accounts or workspaces.
11. **Remote notifications for Claude Code replies** - Detect Claude Code reply completion and forward it to a push-capable bridge outside the Apple Watch flow.
