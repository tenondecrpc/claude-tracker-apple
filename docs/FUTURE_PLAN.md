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
   struct SessionData: Codable {
       let sessionId: String
       let inputTokens: Int
       let outputTokens: Int
       let costUSD: Double
       let durationSeconds: Int
       let timestamp: Date
       let limitResetAt: Date?    // when the 5-hour usage window resets
       let isDoubleLimitActive: Bool  // 2x usage window active
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
       var sessions: [SessionData] = []
       var pendingCompletion: SessionData? = nil
       var limitResetAt: Date? = nil
       var isDoubleLimitActive: Bool = false
   }
   ```
   Persists sessions to `AppStorage` or `UserDefaults`

3. **`ContentView.swift`** — main dashboard:
   - Token usage percentage ring (primary glanceable element)
   - **Reset countdown** — "5hr limit" / "2hr 13min left" until usage window resets
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
   - Uses `WidgetKit` on watchOS (`WKExtensionWidgetFamily`)

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

**Execution order**: Phase 0 → 1 → 2 → 3 → 4 → 5 → 6. Each phase is self-contained and can be executed in a fresh chat with `/do`.

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
