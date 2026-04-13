## Why

Phase 0 documentation discovery confirmed that the Claude Code Stop hook delivers only session metadata via stdin - `session_id`, `transcript_path`, `hook_event_name`, and `stop_hook_active`. Two fields on `SessionInfo` (`limitResetAt`, `isDoubleLimitActive`) have no hook source and can never be populated; they belong to a different data layer (OAuth API → `UsageState`). Removing them now prevents a silent data gap in Phase 3 (stop hook implementation).

## What Changes

- **BREAKING** Remove `limitResetAt: Date?` from `SessionInfo` - limit reset timestamps come from the OAuth API (`UsageState.resetAt5h`), not from per-session hook data
- **BREAKING** Remove `isDoubleLimitActive: Bool` from `SessionInfo` - no hook source exists for this field
- Keep `costUSD: Double` but document that it will always be `0.0` on subscription plans (Claude Code does not expose per-session cost; this field is retained for potential future use)
- Update `MockData.swift` session fixtures to drop the removed fields

## Capabilities

### New Capabilities

_(none - this is a model cleanup, not a new capability)_

### Modified Capabilities

- `session-info`: remove two fields that have no valid data source per Phase 0 research

## Impact

- `Shared/Models.swift` - `SessionInfo` struct loses two fields
- `Tempo Watch Extension/MockData.swift` - session fixtures updated
- Any future Phase 3 shell script or Phase 5 watch receiver that references `limitResetAt` or `isDoubleLimitActive` must not include those fields
