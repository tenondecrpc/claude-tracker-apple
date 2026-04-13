## 1. Data Model

- [x] 1.1 Extend `LocalProjectStat` with `messages7d`, `toolCalls7d`, `totalTokens7d` (Int), and `costEquiv7d` (Double) fields
- [x] 1.2 Add minimal JSONL decode structs: `JNLRecord` (type, timestamp, message?), `JNLMessage` (content?, usage?, model?), `JNLUsage` (input_tokens, output_tokens), `JNLContentBlock` (type) - all with lenient decoding

## 2. JSONL Parsing

- [x] 2.1 Add `parseProjectStats7d(dirURL:cutoffDate:)` static method to `ClaudeLocalDBReader` that iterates `.jsonl` files, filters by mtime >= 7 days ago, reads line-by-line, decodes each line, counts messages (type=user), tool_use blocks (type=assistant), sums tokens, and computes cost per model
- [x] 2.2 Integrate `parseProjectStats7d` into `readProjectStats()` so each `LocalProjectStat` is populated with 7-day fields

## 3. UI - Project Table

- [x] 3.1 Update `projectTable` in `StatsDetailView.swift` to display `messages7d`, `toolCalls7d`, formatted `totalTokens7d`, and formatted `costEquiv7d` instead of "-"
- [x] 3.2 Show "-" when a field is 0; format tokens with `formatTokens()` and cost as `$X.XX`
