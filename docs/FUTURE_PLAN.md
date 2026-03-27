# Claude Code Token Tracker — Apple Watch App

**Architecture**: Claude Code Stop hook → iCloud Drive JSON file → iOS companion monitors file → WatchConnectivity → watchOS haptic + alert screen.

---

## Phase 0: Documentation Discovery

**Goal**: Verify exact APIs before writing any code. Deploy research subagents on:

1. **Claude Code hooks** — read `~/.claude/settings.json` schema; identify what env vars the Stop hook receives (tokens, cost, session ID, limit window, reset timestamp, etc.)
   - Source: `WebFetch` the Claude Code hooks docs
   - Need: exact env var names for `input_tokens`, `output_tokens`, `cost_usd`, and crucially **limit window / reset time**

2. **WatchConnectivity** — `WCSession`, `sendMessage(_:replyHandler:)` vs `transferUserInfo(_:)`, activation states, background delivery
   - Source: Apple Developer docs + any existing patterns in `.agents/skills/swiftui-expert-skill/references/`

3. **NSMetadataQuery for iCloud** — how to watch for file changes in `~/Library/Mobile Documents/com~apple~CloudDocs/`
   - Pattern: `NSMetadataQuery` with `NSMetadataQueryUbiquitousDocumentsScope`

4. **WKHapticType (watchOS)** — exact enum cases: `.notification`, `.directionUp`, `.success`, etc.
   - Also: `WKInterfaceDevice.current().play(_:)`

5. **Local notifications on watchOS** — `UNUserNotificationCenter` for the limit-reset alarm

**Output**: "Allowed APIs" doc saved as `/claude-tracker-applewatch Watch App/APIS.md`

---

## Phase 1: Data Model + Claude Code Stop Hook

**What to implement:**

1. **`SessionData.swift`** — shared Codable struct:
   ```swift
   struct SessionData: Codable, Identifiable {
       let sessionId: String
       let inputTokens: Int
       let outputTokens: Int
       let costUSD: Double
       let durationSeconds: Int
       let timestamp: Date
       let limitResetAt: Date?    // when the 5-hour usage window resets
       let isDoubleLimitActive: Bool  // 2x usage window active

       // Identifiable conformance required by .sheet(item:) in Phase 3
       var id: String { sessionId }
   }
   ```
   File: `claude-tracker-applewatch Watch App/Models/SessionData.swift`

2. **Stop hook shell script** at `~/.claude/hooks/stop-tracker.sh`:
   - Reads env vars provided by Claude Code — exact names confirmed in Phase 0
   - Includes limit window reset timestamp if available
   - Writes JSON to `~/Library/Mobile Documents/com~apple~CloudDocs/ClaudeTracker/latest.json`
   - Creates the iCloud directory if it doesn't exist

3. **Register the hook** in `~/.claude/settings.json`:
   ```json
   { "hooks": { "Stop": [{ "matcher": "", "hooks": [{ "type": "command", "command": "~/.claude/hooks/stop-tracker.sh" }] }] } }
   ```

**Verification checklist:**
- Run `echo $CLAUDE_INPUT_TOKENS` inside a test hook to confirm var names
- Manually trigger hook: check `~/Library/Mobile Documents/com~apple~CloudDocs/ClaudeTracker/latest.json` appears
- Validate JSON parses into `SessionData`

**Anti-pattern guards:**
- Do NOT hardcode token var names without confirming from Phase 0 docs
- Do NOT write to a non-iCloud path (breaks the pipeline)

---

## Phase 2: iOS Companion App — iCloud Monitor + WatchConnectivity

**What to implement:**

1. **`iCloudMonitor.swift`** — watches for `latest.json` changes using `NSMetadataQuery`:
   - On file change → decode `SessionData` → call `WatchRelayManager.send(_:)`
   - Handles first-launch activation and background refresh

2. **`WatchRelayManager.swift`** — `WCSession` sender for iOS:
   - `WCSession.default.activate()`
   - Uses `transferUserInfo(_:)` (reliable background delivery, not `sendMessage` which requires watch to be reachable)
   - Encodes `SessionData` as `[String: Any]` dictionary

3. **`claude_tracker_applewatchApp.swift`** (iOS target) — start monitor on launch

**Files:**
```
claude-tracker-applewatch/          <- iOS container target
├── iCloudMonitor.swift
└── WatchRelayManager.swift
```

**Verification checklist:**
- Drop a valid `latest.json` into iCloud folder manually → confirm `iCloudMonitor` fires
- Confirm `WCSession` delivers `userInfo` to simulator watch

---

## Phase 3: watchOS Core — Receive + Haptic + Dashboard

**What to implement:**

1. **`WatchSessionReceiver.swift`** — `WCSessionDelegate` for watchOS:
   - `session(_:didReceiveUserInfo:)` → decode → publish via `@Observable` `TokenStore`
   - Triggers haptic: `WKInterfaceDevice.current().play(.notification)`

2. **`TokenStore.swift`** — `@Observable` data store:
   ```swift
   @Observable @MainActor
   final class TokenStore {
       private(set) var sessions: [SessionData] = []
       var pendingCompletion: SessionData? = nil   // var: ContentView clears it on dismiss
       private(set) var limitResetAt: Date? = nil
       private(set) var isDoubleLimitActive: Bool = false

       // Ring data — see "Usage Ring" section below
       // Phase 3: mocked. Phase 7: populated from OAuth API via iOS companion.
       private(set) var usageState: UsageState = .mock

       // Persistence: use UserDefaults + JSONEncoder/JSONDecoder directly.
       // Do NOT use @AppStorage inside @Observable — it conflicts with the macro
       // and requires @ObservationIgnored, breaking observation for that property.
   }

   struct UsageState: Codable {
       var utilization5h: Double   // 0.0–1.0
       var utilization7d: Double
       var resetAt5h: Date
       var resetAt7d: Date
       var isMocked: Bool          // true until Phase 7 wires the real API

       // static var (not let) so Date() is evaluated fresh on each access,
       // preventing stale mock countdown values after the first use.
       static var mock: UsageState {
           UsageState(
               utilization5h: 0.42,
               utilization7d: 0.18,
               resetAt5h: Date().addingTimeInterval(2 * 3600 + 13 * 60),
               resetAt7d: Date().addingTimeInterval(4 * 24 * 3600),
               isMocked: true
           )
       }
   }
   ```
   Persist `sessions` to `UserDefaults` via `JSONEncoder`/`JSONDecoder`. Do not use `@AppStorage` inside `@Observable` classes — the macro transforms stored properties in a way that conflicts with property wrappers (compiler error). Use `@ObservationIgnored` only if absolutely needed for a specific wrapper.

3. **`ContentView.swift`** — main dashboard:
   - **Usage ring** — `utilization5h` as primary glanceable element. Displays a `⚠ mock` badge when `usageState.isMocked == true` so it's always visible during development that the data is not real.
   - **Reset countdown** — derived from `usageState.resetAt5h`: "2hr 13min left"
   - **2x indicator** — badge or color change when double limits are active
   - `.sheet(item: $store.pendingCompletion)` → `CompletionView`

4. **`CompletionView.swift`** — task completion alert:
   - Full-screen overlay on task completion
   - Shows token count and cost
   - Dismiss via tap

**Verification checklist:**
- Send mock `SessionData` from iOS simulator → watch shows haptic + `CompletionView` appears
- `pendingCompletion` clears after dismissal
- Countdown shows correct time remaining

---

## Phase 4: Limit Reset Alarm

**What to implement:**

**`ResetAlarmManager.swift`** — schedules a local notification + strong haptic when the limit window resets:
- `UNUserNotificationCenter` — schedule notification at `limitResetAt`
- On trigger: `WKInterfaceDevice.current().play(.notification)` (strongest haptic)
- Reschedules automatically when a new `SessionData` arrives with an updated `limitResetAt`

**Why this phase matters**: The most-requested feature from the community. Users want to know the exact moment they can resume full usage — not just track what they've used.

**Verification checklist:**
- Schedule alarm 30 seconds in the future with mock date → confirm notification fires + haptic plays
- Confirm alarm reschedules when `limitResetAt` changes

---

## Phase 5: Stats Dashboard + Complications

**What to implement:**

1. **`StatsView.swift`** — scrollable list of past sessions with token bars (using `RoundedRectangle` fill proportional to max session)

2. **`TokenComplication.swift`** — Watch face complication:
   - Graphic corner: usage % + countdown to reset (primary)
   - Circular: usage percentage
   - Uses `WidgetKit` on watchOS — same `WidgetFamily` API as iOS, accessory families only: `.accessoryCircular`, `.accessoryCorner`, `.accessoryRectangular`, `.accessoryInline` (`WKExtensionWidgetFamily` does not exist)

3. **`ComplicationProvider.swift`** — `TimelineProvider` that reads from shared `UserDefaults` (App Group)

**Anti-pattern guards:**
- Complications require App Group entitlement — set up in Xcode before writing code
- `WidgetKit` on watchOS uses same API as iOS but limited families — verify supported families in Phase 0
- Complication timeline must account for the reset countdown (entries needed every ~15 min)

---

## Phase 6: Final Verification

- End-to-end test: run a real Claude Code session → hook fires → JSON in iCloud → iOS relays → watch shows haptic + dashboard updates
- Confirm reset countdown is accurate and alarm fires at the right time
- Confirm 2x indicator appears/disappears correctly
- Grep for deprecated APIs: `foregroundColor`, `NavigationView`, `ObservableObject`
- Verify `@State` is always `private`
- Verify no `sendMessage` (use `transferUserInfo` for reliability)
- Confirm hook script has `chmod +x` and runs without errors

---

**Execution order**: Phase 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7. Each phase is self-contained and can be executed in a fresh chat with `/do`.

---

## Phase 7: Real Usage Ring — Anthropic OAuth API

**Context**: Phases 3–6 build the ring using `UsageState.mock`. This phase replaces the mock with real data from the Anthropic OAuth API. The ring UI, countdown, and reset alarm **do not change** — only the data source.

**Why deferred**: OAuth PKCE adds meaningful iOS complexity. Building the ring against a mock first lets all other features stabilize before introducing auth.

**What the API provides** (confirmed from [claude-usage-bar](https://github.com/Blimp-Labs/claude-usage-bar)):
- `GET /api/oauth/usage` → `five_hour.utilization`, `five_hour.resets_at`, `seven_day.utilization`, `seven_day.resets_at`
- Auth: OAuth 2.0 PKCE. Access token + refresh token, auto-refresh 5 min before expiry.
- Credentials stored at `~/.config/...` on mac; on iOS use Keychain.

**What to implement:**

1. **`AnthropicAPIClient.swift`** (iOS target) — OAuth PKCE client:
   - Browser-based sign-in via `ASWebAuthenticationSession`
   - Token storage in iOS Keychain (not UserDefaults)
   - `needsRefresh()` → proactive refresh with 300-second leeway
   - Exponential backoff on 429, up to 60-minute cap
   - Graceful logout on `invalid_grant` / persistent 401

2. **`UsageStatePoller.swift`** (iOS target) — polls `/api/oauth/usage`:
   - 15-minute default interval (30-minute recommended; 5-minute discouraged)
   - Applies reset-timestamp reconciliation:
     - If server omits `resets_at`: preserve previous value
     - If utilization drops after time elapsed: advance reset by bucket duration (5h or 7d)
     - If server provides a new valid timestamp: trust it
   - On new `UsageState`: relay to watch via `transferUserInfo` (same path as `SessionData`)

3. **`TokenStore` update** — set `usageState.isMocked = false` once first real poll succeeds. The `⚠ mock` badge disappears automatically.

4. **`ResetAlarmManager` update** — already reads `usageState.resetAt5h`; no changes needed once real data flows.

**Verification checklist:**
- Sign in via OAuth → confirm credentials stored in Keychain
- Poll fires → `UsageState.isMocked` becomes `false` → mock badge disappears from watch
- Simulate 429 → confirm backoff increases correctly
- Simulate server dropping `resets_at` → confirm previous value preserved
- Simulate utilization drop (rollover) → confirm reset time advances by 5h
- Revoke token → confirm graceful logout, mock badge reappears

**Anti-pattern guards:**
- Do NOT store OAuth tokens in UserDefaults — use Keychain
- Do NOT poll more than every 15 minutes in production
- Do NOT show the ring as "real" until `isMocked == false` — the badge is the contract

---

## Future: Windows / Cross-Platform Support

The current architecture uses iCloud as the transport layer (Mac-only). To support Windows in the future, replace iCloud with an **HTTP relay** — everything else stays the same.

```
Stop hook (any OS) → curl POST to relay → iOS app (polling/WebSocket) → WatchConnectivity → watch
```

**Relay options** (pick one when the time comes):
- **ntfy.sh** — zero backend, hook does a single `curl` POST. Simplest. Downside: token/cost data goes to a public server.
- **Supabase Realtime** — free tier, real-time iOS SDK, data stays in your account.
- **Cloudflare Worker + KV** — cheap, fast, requires a small deploy.

**What changes:**
- `stop-tracker.sh` → add a `curl -X POST` to a configurable endpoint (keep iCloud write as default for Mac)
- `iCloudMonitor.swift` → replace `NSMetadataQuery` with a polling timer or WebSocket subscriber

**What does NOT change:** `SessionData` model, WatchConnectivity relay, all watchOS code.

---

## Reference: claude-usage-bar (Blimp-Labs)

**Repo**: https://github.com/Blimp-Labs/claude-usage-bar
**What it is**: macOS menu bar app that shows real-time Claude API utilization (5-hour and 7-day windows) via the Anthropic OAuth API. No hooks, no Apple Watch, no iCloud.

### Architecture

```
Anthropic OAuth API (/api/oauth/usage) ← polling (5–60 min)
         ↓
  UsageService (SwiftUI @Published)
         ↓
  MenuBarIconRenderer  →  two progress bars (5h + 7d)
  PopoverView          →  percentages, per-model breakdown, chart, cost
  NotificationService  →  threshold-crossing alerts
```

### What the API returns

Endpoint: `GET /api/oauth/usage`

```
five_hour:
  utilization  — float 0.0–1.0 (percentage of 5-hour window consumed)
  resets_at    — ISO 8601 timestamp

seven_day:
  utilization  — float 0.0–1.0
  resets_at    — ISO 8601 timestamp

extra_usage (optional):
  utilization  — paid credit consumption
  resets_at    — ISO 8601 timestamp
  amount       — integer in minor units (cents), converted to USD for display
```

Per-model breakdowns available for Opus and Sonnet separately.

**Auth**: OAuth 2.0 PKCE flow. Credentials stored at `~/.config/claude-usage-bar/credentials.json` (access token + refresh token + expiry). Auto-refreshed 5 minutes before expiry.

### Comparison with ClaudeTracker

| Dimension | claude-usage-bar | ClaudeTracker |
|---|---|---|
| Platform | macOS menu bar only | macOS + iOS + Apple Watch |
| Data source | Anthropic OAuth API (polling) | Claude Code Stop hook (real-time) |
| Data granularity | Aggregate utilization % for 5h/7d windows | Per-session tokens, cost, duration |
| Reset tracking | `resets_at` from API (authoritative) | Planned via hook env vars (unconfirmed) |
| Haptic feedback | None | Core feature (watchOS) |
| Latency | 5–60 min poll interval | Immediate on session end |
| Session-level data | No | Yes (tokens, cost per session) |
| Historical data | 30-day, downsampled, local JSON | Planned (Phase 5) |
| Per-model breakdown | Yes (Opus vs Sonnet) | Not planned |
| 7-day window | Yes | Not yet in scope |
| Complications/widgets | No | Planned (Phase 5) |
| Cross-device | No | Core architecture |

### Strengths of claude-usage-bar worth adopting

**1. OAuth API as authoritative utilization source**
The API provides exact `utilization` (0.0–1.0) for the 5-hour window — more reliable than trying to estimate it from per-session token counts in hooks. The `resets_at` timestamp is the definitive reset time.

**2. Reset timestamp reconciliation**
When the server temporarily drops `resets_at`, the app applies smart fallback logic:
- Preserve previous reset timestamp if server omits it
- Detect rollover when utilization drops after time has elapsed → advance reset by bucket duration
- Trust newly provided server timestamps when they appear

**3. Threshold-crossing detection (not level)**
Notifications fire only on the upward transition (below → above threshold), not repeatedly while above. Avoids alert fatigue.

**4. Exponential backoff on 429**
If the API rate-limits, polling interval backs off up to 60 minutes. Worth mirroring in the iOS companion if it polls the API.

**5. 7-day window + extra usage (paid credits)**
Two windows matter: `five_hour` for short-term limits, `seven_day` for the weekly budget. Extra usage tracks paid credits in USD.

**6. Atomic writes + dirty flag flush**
Historical data written atomically every 5 minutes (dirty flag), not on every update. Prevents corruption and reduces I/O.

**7. Per-model breakdown**
Opus and Sonnet have separate utilization — useful for the stats view (Phase 5).

### Weaknesses (where ClaudeTracker is superior)

- No Apple Watch / haptic feedback
- Polling latency (5–60 min) vs our instant hook trigger
- No per-session breakdown (cost, duration, token counts)
- No complications or cross-device push
- No reset alarm on the watch

### Impact on the roadmap

These improvements integrate cleanly with the existing 6-phase plan:

**Phase 0 addition** — Research the Anthropic OAuth API:
- Confirm `/api/oauth/usage` response schema and field names
- Confirm OAuth 2.0 PKCE flow and token storage format
- Determine if the iOS app can authenticate independently (separate from macOS)

**Phase 1 addition** — Extend `SessionData` / add `UsageState`:
```swift
struct UsageState: Codable {
    let utilization5h: Double       // 0.0–1.0 from API
    let utilization7d: Double
    let resetAt5h: Date
    let resetAt7d: Date
    let extraUsageUSD: Double?      // paid credits consumed
    let utilizationOpus5h: Double?
    let utilizationSonnet5h: Double?
}
```
The iOS app maintains a `UsageState` refreshed by polling the API, separate from per-session `SessionData` written by hooks. Both flow to the watch.

**Phase 2 addition** — iOS companion polls the OAuth API:
- Add `AnthropicAPIClient.swift` with PKCE OAuth + token refresh
- Poll `/api/oauth/usage` every 15–30 minutes (match claude-usage-bar recommendation)
- Apply reset-timestamp reconciliation logic from claude-usage-bar
- Relay `UsageState` to watch via `transferUserInfo` independently of hook events

**Phase 3 update** — ContentView ring uses real utilization %:
- Show `usageState.utilization5h` as the primary ring (authoritative, not estimated)
- Show `usageState.utilization7d` as secondary ring or badge
- Countdown derived from `usageState.resetAt5h` (API-provided, no guessing)
- Add 7-day window indicator

**Phase 4 update** — ResetAlarmManager uses API `resetAt5h`:
- Replace inferred reset time with `UsageState.resetAt5h` from the API
- Apply reconciliation: preserve previous value when API drops timestamp, detect rollover
- Reschedule when `UsageState` is updated

**Phase 5 addition** — StatsView per-model breakdown:
- Show Opus vs Sonnet utilization breakdown using API data
- Show extra usage (paid credits) as a separate row

**New Phase 5.5 (optional): 7-day window complication**
- Add a second complication timeline for the 7-day window
- Uses `UsageState.utilization7d` + `resetAt7d`
