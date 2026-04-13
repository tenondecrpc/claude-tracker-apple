## Context

`SessionInfo` in `Shared/Models.swift` has two fields with no valid data source:
- `limitResetAt: Date?` - limit reset timestamps are account-level OAuth data, not per-session hook data
- `isDoubleLimitActive: Bool` - no hook env var or transcript field exists for this

Phase 0 confirmed the Stop hook delivers only `session_id`, `transcript_path`, `hook_event_name`, `stop_hook_active` via stdin. Token/cost data requires parsing the transcript JSONL. There is no mechanism by which the hook can learn `limitResetAt` or `isDoubleLimitActive`.

## Goals / Non-Goals

**Goals:**
- Remove the two fields that can never be populated
- Keep `costUSD` (always `0.0` on subscription) for structural parity with future paid-plan support
- Keep `MockData.swift` compiling and representative

**Non-Goals:**
- Changing the Stop hook script (Phase 3)
- Changing how `WatchConnectivity` encodes/decodes payloads (Phase 2/5)
- Any UI changes

## Decisions

**Remove both fields entirely (vs. keeping as optional/computed)**

Both fields are `let` constants - they cannot be lazily populated. Making them `Optional` would just defer the problem: every callsite would need to unwrap a value that is always `nil`. Removal is cleaner and eliminates the false promise that this data exists.

**Keep `costUSD: Double` at `0.0`**

`costUSD` could theoretically be non-zero if Anthropic ever exposes per-session cost in hook data (e.g., for API-key users). Keeping the field costs nothing and avoids a second breaking change later.

## Risks / Trade-offs

- **BREAKING change** → No external consumers exist yet; all code is within this repo and nothing outside the app uses `SessionInfo` over a wire. Risk: none.
- `costUSD` is always `0.0` → UI showing cost will always show zero. Mitigation: Phase 3 can compute cost from token counts + model pricing tables if desired; the field is there when needed.

## Migration Plan

1. Remove fields from `SessionInfo` in `Shared/Models.swift`
2. Fix `MockData.swift` fixtures (remove the two arguments from initializers)
3. Build - verify no other call sites remain (there are none in current codebase)
