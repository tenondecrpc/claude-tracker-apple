## Why

The project breakdown table currently shows only session counts - all other columns (Messages, Tools, Tokens, Cost) display "-". The competitor's app shows fully populated per-project stats, making it the most visible gap in our feature set. Filling these columns gives users actionable insight into where their usage and cost actually go.

## What Changes

- Parse JSONL session files per project to extract message counts, tool call counts, token usage (by model), and compute API-equivalent cost
- Extend `LocalProjectStat` with `messages`, `toolCalls`, `totalTokens`, and `costEquiv` fields
- Populate all 5 table columns in the project breakdown - **scoped to the 7-day filter only** (other filters remain unchanged)
- Fix summary stats bar: Tool Calls and Subagents currently show 0 because they use incomplete data sources; align them with the 7-day JSONL-derived totals

## Capabilities

### New Capabilities
- `project-jsonl-stats`: Parse per-project JSONL files to derive 7-day message, tool call, token, and cost breakdowns

### Modified Capabilities
- `session-info`: Extend `LocalProjectStat` model with per-project aggregate fields derived from JSONL parsing

## Impact

- **Code**: `ClaudeLocalDBReader.swift` (new JSONL parsing logic, extended model), `StatsDetailView.swift` (render real data instead of "-")
- **Performance**: JSONL parsing runs on a background thread; files can be large. Must limit scanning to sessions with timestamps in the last 7 days and avoid reading entire files when possible
- **Dependencies**: No new dependencies - uses Foundation `JSONDecoder` on raw JSONL lines
