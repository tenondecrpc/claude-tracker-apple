## Context

The project breakdown table in `StatsDetailView` has headers for 5 data columns (Sessions, Messages, Tools, Tokens, Cost) but only Sessions is populated - the rest show "-". The underlying data lives in per-project JSONL files at `~/.claude/projects/<encoded-path>/`. Each `.jsonl` file is a session containing typed records (`user`, `assistant`, `system`, `file-history-snapshot`, `last-prompt`). Assistant records include a `message.usage` object with token counts and a `message.model` field. Tool calls are `tool_use` blocks inside `message.content`.

Currently `ClaudeLocalDBReader.readProjectStats()` only counts `.jsonl` files per directory (session count). No JSONL content is parsed.

## Goals / Non-Goals

**Goals:**
- Populate Messages, Tools, Tokens, and Cost columns in the project table for the 7-day view
- Parse JSONL files to extract per-project aggregates: user message count, tool_use block count, total tokens (input+output), and API-equivalent cost
- Keep parsing performant - run on a background thread, only process sessions with recent timestamps

**Non-Goals:**
- Populating these columns for ALL HISTORY or custom date range filters (future work)
- Per-session drill-down or session-level detail
- Changing the summary stats bar (it already works; tool calls/subagents values come from different sources)

## Decisions

### 1. Parse JSONL inline during `load()` - no separate cache

**Choice**: Read and parse JSONL files directly in the existing `Task.detached` block inside `load()`.

**Why**: Adding a second cache file introduces sync complexity. The JSONL files are local and parsing is I/O-bound. For a menu bar app that loads on open, a single-pass read is simplest.

**Alternative considered**: Build a separate `project-stats-cache.json` - rejected because it adds invalidation logic and the data changes every session.

### 2. Only scan sessions modified in the last 7 days

**Choice**: Use file modification date (`attributesOfItem` → `.modificationDate`) as a fast pre-filter. Only parse files whose mtime is within the last 7 days. Then confirm with first record's `timestamp` field.

**Why**: A user with hundreds of sessions shouldn't pay the cost of parsing old files. File mtime is a cheap syscall. This gives O(recent) instead of O(all) parsing cost.

### 3. Extend `LocalProjectStat` with optional 7d fields

**Choice**: Add `messages7d`, `toolCalls7d`, `totalTokens7d`, `costEquiv7d` as `Int` / `Double` fields to `LocalProjectStat`.

**Why**: Keeps the model flat and simple. The table only needs these for the 7-day view. The `sessionCount` field remains the all-time count.

### 4. Cost calculation uses the same model-based heuristic as `computeCostEquiv()`

**Choice**: Reuse the existing pricing constants (Opus: $15/$75 per M in/out, Sonnet: $3/$15, Haiku: $1/$5) to compute per-project cost.

**Why**: Consistency with the summary bar. These are API-equivalent costs, not actual billing.

### 5. JSONL record schema - extract only what's needed

Per line, decode a minimal struct:
- `type` → filter for `"user"` (count messages) and `"assistant"` (extract tool calls + usage)
- `timestamp` → for date filtering
- `message.content[]` → count `tool_use` type blocks (assistant only)
- `message.usage.input_tokens`, `output_tokens` → token counts
- `message.model` → for cost tier lookup

Skip `file-history-snapshot`, `system`, and `last-prompt` types entirely.

## Risks / Trade-offs

- **Large projects with many sessions**: Mitigated by 7-day mtime pre-filter. Worst case is a project with many recent sessions, but even 50 sessions × ~1MB each parses in under a second on M1.
- **JSONL schema changes**: Claude Code's JSONL format is undocumented and may change. Using lenient decoding (`decodeIfPresent`, `try?`) so missing fields degrade gracefully to 0 rather than crash.
- **File I/O on every reload**: Acceptable for a menu bar app that reloads on window open. Could add in-memory caching later if needed.
