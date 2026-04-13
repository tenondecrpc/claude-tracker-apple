# APIS.md - Confirmed API Reference

Phase 0 research output. All signatures verified before Phase 1+ implementation.

---

## 1. Anthropic OAuth API

**Sources**: claude-usage-bar source (`UsageService.swift`, `UsageModel.swift`, `mock-server.py`)

### OAuth PKCE Flow

| Parameter | Value |
|---|---|
| Authorization endpoint | `https://claude.ai/oauth/authorize` |
| Token endpoint | `https://platform.claude.com/v1/oauth/token` |
| Client ID | `9d1c250a-e61b-44d9-88ed-5944d1962f5e` |
| Redirect URI | `https://platform.claude.com/oauth/code/callback` |
| Scopes | `user:profile user:inference` |
| PKCE method | `S256` |
| Challenge | `base64url(SHA256(verifier))` |

**Authorization URL query parameters:**
```
code=true
client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e
response_type=code
redirect_uri=https://platform.claude.com/oauth/code/callback
scope=user:profile user:inference
code_challenge=<base64url(SHA256(verifier))>
code_challenge_method=S256
state=<random>
```

**Callback note**: Uses a "paste code" flow - the redirect lands in the browser and the user pastes a `<code>#<state>` string. Code = part before `#`, state = part after.

**Claude Code credential reuse**: Claude Code does NOT expose reusable OAuth tokens. `~/.claude/.claude.json` contains account metadata (`oauthAccount.emailAddress`, `displayName`, `accountUuid`) but no `access_token` or `refresh_token`. `~/.claude/credentials.json` exists but is empty (3 bytes). Each app (Tempo, claude-usage-bar, etc.) MUST manage its own OAuth tokens via its own token exchange. The email from `.claude.json` can be read for display purposes only.

**Token exchange - POST body (JSON):**
```json
{
  "grant_type": "authorization_code",
  "code": "<code from callback>",
  "state": "<state>",
  "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  "redirect_uri": "https://platform.claude.com/oauth/code/callback",
  "code_verifier": "<original verifier>"
}
```

**Token response fields**: `access_token`, `refresh_token`, `expires_in`, `scope`

**Token refresh - POST body (JSON):**
```json
{
  "grant_type": "refresh_token",
  "refresh_token": "<refresh_token>",
  "client_id": "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
  "scope": "user:profile user:inference"
}
```

**Refresh trigger**: proactively check `needsRefresh()` before each call; also retry on any `401` by forcing refresh then replaying once. Invalidate session on permanent failure when token is expired.

### Usage Endpoint

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <access_token>
anthropic-beta: oauth-2025-04-20
```

**Userinfo endpoint (bonus):**
```
GET https://api.anthropic.com/api/oauth/userinfo
→ { "email": "...", "name": "..." }
```

### Usage Response Shape

```json
{
  "five_hour": {
    "utilization": 25.0,
    "resets_at": "2024-01-15T14:30:45.123456+00:00"
  },
  "seven_day": {
    "utilization": 45.0,
    "resets_at": "2024-01-20T14:30:45.123456+00:00"
  },
  "seven_day_opus": {
    "utilization": 70.0,
    "resets_at": "..."
  },
  "seven_day_sonnet": {
    "utilization": 15.0,
    "resets_at": "..."
  },
  "seven_day_oauth_apps": null,
  "seven_day_cowork": null,
  "iguana_necktie": null,
  "extra_usage": {
    "is_enabled": false,
    "monthly_limit": null,
    "used_credits": null,
    "utilization": null
  }
}
```

**Field notes:**
- `utilization` - `Double?`, range **0–100** (not 0–1). Divide by 100 when mapping to `UsageState.utilization5h/7d`.
- `resets_at` - ISO 8601 with microseconds: `"2024-01-15T14:30:45.123456+00:00"`
- `seven_day_opus` / `seven_day_sonnet` - nullable; only present when per-model tracking is active
- `used_credits` / `monthly_limit` - denominated in **cents**
- `iguana_necktie` - reserved/future field, always null

**Mapping to `UsageState`:**
```swift
UsageState(
    utilization5h: response.five_hour.utilization / 100.0,
    utilization7d: response.seven_day.utilization / 100.0,
    resetAt5h: ISO8601DateFormatter().date(from: response.five_hour.resets_at),
    resetAt7d: ISO8601DateFormatter().date(from: response.seven_day.resets_at),
    isMocked: false
)
```

### Rate Limits & 429 Handling

- On `429`: exponential backoff, capped at **1 hour**
- Check `Retry-After` header (seconds); if absent, double the current interval
- Formula: `min(max(retryAfter ?? currentInterval, currentInterval * 2), 3600)`
- Default polling target: **15 minutes** for our app (claude-usage-bar uses 30 min)
- Token storage: **iOS Keychain only** - never `UserDefaults`

---

## 2. Claude Code Stop Hook

**⚠️ Critical finding**: data is delivered via **stdin as JSON**, NOT as environment variables. The earlier `PLAN.md` reference to `echo $CLAUDE_INPUT_TOKENS` was a hypothesis - env vars do not exist. Verify with a debug hook that dumps stdin to file.

### Stdin JSON Payload

```json
{
  "session_id": "abc123-...",
  "transcript_path": "/Users/you/.claude/projects/.../session.jsonl",
  "hook_event_name": "Stop",
  "stop_hook_active": true
}
```

| Field | Type | Notes |
|---|---|---|
| `session_id` | string | Unique session identifier |
| `transcript_path` | string | Absolute path to session JSONL transcript |
| `hook_event_name` | string | Always `"Stop"` for Stop hooks |
| `stop_hook_active` | bool | Whether a Stop hook is active |

### What is NOT in the Stop hook payload

- Input/output tokens - **not present**
- Cost in USD - **not present**
- Duration - **not present**
- Context window breakdown - **not present**
- Utilization % or reset timestamps - **not present** (OAuth API only)

### How to get token/cost data from the hook

The `transcript_path` points to the session's JSONL file. Each line is a message; assistant messages contain a `usage` object:

```json
{
  "message": {
    "usage": {
      "input_tokens": 3,
      "output_tokens": 75,
      "cache_read_input_tokens": 7224,
      "cache_creation_input_tokens": 1528
    }
  }
}
```

The shell script must sum these across all lines to compute session totals:

```bash
#!/bin/bash
# Read stdin JSON
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['session_id'])")
TRANSCRIPT=$(echo "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['transcript_path'])")

# Sum tokens from transcript
INPUT_TOKENS=$(grep -o '"input_tokens":[0-9]*' "$TRANSCRIPT" | awk -F: '{sum+=$2} END {print sum}')
OUTPUT_TOKENS=$(grep -o '"output_tokens":[0-9]*' "$TRANSCRIPT" | awk -F: '{sum+=$2} END {print sum}')
```

**Cost**: Claude Code sets `costUSD: 0` in its local DB (subscription plan, no per-token billing). The hook approach would require hardcoding model pricing tables - uncertain value. Consider omitting `costUSD` from `SessionInfo` or always setting it to 0.

**Duration**: calculate from first/last timestamps in the transcript JSONL.

### Impact on `SessionInfo` model

Current fields and their sources:

| Field | Source | Status |
|---|---|---|
| `sessionId` | `session_id` from stdin | ✅ available |
| `inputTokens` | Sum from transcript JSONL | ✅ available (requires parsing) |
| `outputTokens` | Sum from transcript JSONL | ✅ available (requires parsing) |
| `costUSD` | No direct source | ⚠️ set to 0 or remove |
| `durationSeconds` | First/last timestamps in transcript | ✅ available (requires parsing) |
| `timestamp` | Session start timestamp in transcript | ✅ available |
| `limitResetAt` | OAuth API only | ❌ remove from SessionInfo |
| `isDoubleLimitActive` | No hook source | ❌ remove from SessionInfo |

**Recommendation**: remove `limitResetAt` and `isDoubleLimitActive` from `SessionInfo` - they cannot be populated from the Stop hook and are not per-session data. Limit/reset info lives in `UsageState` (from OAuth).

### Hook registration (`~/.claude/settings.json`)

```json
{
  "hooks": {
    "Stop": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "~/.claude/hooks/stop-tracker.sh"
      }]
    }]
  }
}
```

**Debug hook to verify stdin schema (run first):**
```bash
#!/bin/bash
cat > /tmp/hook-debug.json
```

---

## 3. Claude Code Local DB

**Format**: JSONL files (no SQLite)

### File Structure

```
~/.claude/
├── stats-cache.json          ← pre-aggregated stats (/stats command reads this)
├── sessions/<pid>.json       ← active session metadata
├── projects/<escaped-path>/
│   ├── <session-uuid>.jsonl  ← per-message API responses
│   └── subagents/
│       └── agent-<id>.jsonl  ← subagent messages
└── session-env/<uuid>/       ← shell environment snapshots
```

### `stats-cache.json` schema (Phase 8 target)

```json
{
  "version": 2,
  "lastComputedDate": "2026-03-26",
  "totalSessions": 180,
  "totalMessages": 11715,
  "firstSessionDate": "2026-03-08T01:58:18.205Z",
  "dailyActivity": [
    { "date": "2026-03-09", "messageCount": 721, "sessionCount": 6, "toolCallCount": 250 }
  ],
  "dailyModelTokens": [
    { "date": "2026-03-09", "tokensByModel": { "claude-opus-4-6": 33337, "claude-sonnet-4-6": 75308 } }
  ],
  "modelUsage": {
    "claude-opus-4-6": {
      "inputTokens": 75767,
      "outputTokens": 524165,
      "cacheReadInputTokens": 136073648,
      "cacheCreationInputTokens": 7355713,
      "costUSD": 0
    }
  },
  "longestSession": { "sessionId": "...", "duration": 42428787, "messageCount": 288, "timestamp": "..." },
  "hourCounts": { "9": 16, "22": 19 },
  "totalSpeculationTimeSavedMs": 0
}
```

**Notes:**
- `costUSD: 0` throughout - subscription plan, no per-token cost tracked
- `duration` in `longestSession` is in **milliseconds**
- Daily data only - no per-session aggregates in the cache
- Per-session token totals require summing across each message in the JSONL transcript

### `sessions/<pid>.json` schema

```json
{
  "pid": 27369,
  "sessionId": "c5f3a65f-ac07-48e6-8329-cdc5b755c983",
  "cwd": "/Users/tenonde/Projects/personal/tempo-for-claude",
  "startedAt": 1774655137618,
  "kind": "interactive",
  "entrypoint": "cli"
}
```

### Per-message JSONL schema (inside project JSONL files)

```json
{
  "parentUuid": "...",
  "isSidechain": false,
  "message": {
    "model": "claude-opus-4-6",
    "id": "msg_01...",
    "role": "assistant",
    "usage": {
      "input_tokens": 3,
      "output_tokens": 75,
      "cache_read_input_tokens": 7224,
      "cache_creation_input_tokens": 1528,
      "service_tier": "standard",
      "inference_geo": "not_available"
    }
  }
}
```

### Phase 8 StatsView strategy

Read `~/.claude/stats-cache.json` directly. Provides:
- Activity heatmap (daily session + message counts)
- Model breakdown (tokens per model per day)
- Session count, message count, hour distribution
- Longest session metadata

Does NOT provide: per-session token totals, cost, or per-session duration.

---

## 4. WatchConnectivity

### `transferUserInfo` vs `sendMessage`

| | `transferUserInfo` | `sendMessage` |
|---|---|---|
| Background delivery | ✅ Yes | ❌ No |
| Watch off wrist | ✅ Queues | ❌ Fails |
| Queue persistence | ✅ Disk-backed, survives reboots | ❌ None |
| Requires reachability | ❌ No | ✅ Yes |
| **Use for** | `UsageState` polls, `SessionInfo` events | Not needed in this project |

**Rule**: use `transferUserInfo` for everything. Never depend on `isReachable`.

**Stale queue management for `UsageState`** (cancel old polls before sending new):
```swift
WCSession.default.outstandingUserInfoTransfers
    .filter { ($0.userInfo["type"] as? String) == "UsageState" }
    .forEach { $0.cancel() }
WCSession.default.transferUserInfo(newPayload)
```
**Do NOT cancel `SessionInfo` transfers** - every session event must be delivered.

### Activation Sequence

Set delegate **before** calling `activate()` - call both in `applicationDidFinishLaunching`:
```swift
WCSession.default.delegate = self
WCSession.default.activate()
```

`.inactive` state exists on iOS only (watch pairing transitions). watchOS goes directly `.notActivated → .activated`.

### Required Delegate Methods

**iOS** (3 required):
- `activationDidCompleteWith(session:state:error:)`
- `sessionDidBecomeInactive(_:)` - stop sending
- `sessionDidDeactivate(_:)` - call `WCSession.default.activate()` to re-activate for new watch

**watchOS** (1 required):
- `activationDidCompleteWith(session:state:error:)`

**Essential (optional in protocol):**
- `session(_:didReceiveUserInfo:)` - called on a **background thread**; dispatch to `@MainActor` before mutating `TokenStore`

### Payload Encoding with Type Discriminator

```swift
// Sender (iOS) - add "type" key to every payload
var info = usageState.toUserInfo()        // manual [String: Any] conversion
info["type"] = "UsageState"
WCSession.default.transferUserInfo(info)

// Receiver (watchOS)
func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    DispatchQueue.main.async {
        switch userInfo["type"] as? String {
        case "UsageState": // decode and apply
        case "SessionInfo": // decode, haptic, set pendingCompletion
        default: break
        }
    }
}
```

### Payload Size

No concern - `SessionInfo` + `UsageState` are well under the ~65 KB practical limit.

---

## 5. NSMetadataQuery - iCloud File Watching (iOS)

### Setup

```swift
let query = NSMetadataQuery()
query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
query.predicate = NSPredicate(
    format: "%K == %@",
    NSMetadataItemFSNameKey,
    "latest.json"
)
query.start()  // must run on main run loop
```

### Required Observers

```swift
// On change (what you want):
NotificationCenter.default.addObserver(
    forName: .NSMetadataQueryDidUpdate,
    object: query,
    queue: .main
) { [weak self] _ in
    self?.handleQueryResults(query)
}

// On initial gather:
NotificationCenter.default.addObserver(
    forName: .NSMetadataQueryDidFinishGathering,
    object: query,
    queue: .main
) { [weak self] _ in
    self?.handleQueryResults(query)
}
```

### Reading the File Safely

```swift
func handleQueryResults(_ query: NSMetadataQuery) {
    query.disableUpdates()       // ← required, prevents crash
    defer { query.enableUpdates() }

    guard let item = query.result(at: 0) as? NSMetadataItem,
          let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL
    else { return }

    // Check download status first
    let status = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
    guard status == NSMetadataUbiquitousItemDownloadingStatusCurrent else {
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        return  // didUpdate will fire again when download completes
    }

    // NSFileCoordinator required for iCloud files
    let coordinator = NSFileCoordinator()
    var error: NSError?
    coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { url in
        let data = try? Data(contentsOf: url)
        // decode SessionInfo from data
    }
}
```

**Gotchas:**
- `disableUpdates()` / `enableUpdates()` are mandatory around result access - skipping causes crashes
- `NSFileCoordinator` is required even for reads - iCloud daemon uses file coordination
- Must start on main run loop - background queues without a run loop silently fail
- When app is backgrounded, `NSMetadataQueryDidUpdate` stops firing - restart query on `applicationDidBecomeActive`

### Required Entitlement

`com.apple.developer.ubiquity-container-identifiers` - added automatically by Xcode when enabling iCloud capability with "iCloud Documents" checked.

---

## 6. WKHapticType (watchOS)

```swift
WKInterfaceDevice.current().play(.notification)
```

**Recommended cases for Tempo:**

| Event | Type | Pattern |
|---|---|---|
| Session completed | `.notification` | Double pulse - standard "something happened" |
| Limit reset | `.success` | Two ascending pulses - confirms positive event |
| Warning (approaching limit) | `.failure` | Descending buzz - conveys urgency |
| Softer warning | `.retry` | Gentler prompt |

**Full enum** (watchOS 1.0+): `.notification`, `.directionUp`, `.directionDown`, `.success`, `.failure`, `.retry`, `.start`, `.stop`, `.click`, `.navigationGenericManeuver`, `.navigationLeftTurn`, `.navigationRightTurn`, `.underwaterDepthPrompt` (watchOS 5+)

**Note**: haptics only fire in foreground or via notification delivery. For background haptics, use `UNUserNotificationCenter` with `.sound = .default` - the OS triggers the haptic automatically on notification delivery.

---

## 7. UNUserNotificationCenter (watchOS)

**Available**: watchOS 3.0+. Fully independent of iOS - no paired iPhone needed at scheduling time.

**No special entitlement** required for local notifications.

### Permission Request

```swift
let granted = try await UNUserNotificationCenter.current()
    .requestAuthorization(options: [.alert, .sound, .badge])
```

### Schedule at Specific Date

```swift
let content = UNMutableNotificationContent()
content.title = "Claude Limit Reset"
content.body = "5-hour window has reset - you're good to go."
content.sound = .default  // also triggers watch haptic

let components = Calendar.current.dateComponents(
    [.year, .month, .day, .hour, .minute, .second],
    from: resetAt5h
)
let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
let request = UNNotificationRequest(
    identifier: "reset-5h",   // deterministic ID for cancellation
    content: content,
    trigger: trigger
)
UNUserNotificationCenter.current().add(request)
```

### Cancel and Reschedule

```swift
// Cancel before rescheduling (e.g. on each UsageState update)
UNUserNotificationCenter.current()
    .removePendingNotificationRequests(withIdentifiers: ["reset-5h"])

// Then schedule with updated resetAt5h
```

**Key behaviors:**
- Local notifications are delivered by the OS kernel even when the app is not running - no background entitlement needed
- `content.sound = .default` on watchOS triggers the haptic automatically - no need to call `WKInterfaceDevice.current().play()` separately
- Pending notification limit: 64 per app (not a concern here)
- Custom notification UI requires `WKNotificationScene` (Phase 6+ consideration)
