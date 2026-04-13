## ADDED Requirements

### Requirement: JSONL session parsing for per-project stats
The system SHALL parse `.jsonl` session files in `~/.claude/projects/<project>/` to extract per-project usage statistics for the last 7 days. Only files with a modification date within the last 7 days SHALL be parsed.

#### Scenario: Parse user messages for message count
- **WHEN** a JSONL file contains records with `"type": "user"`
- **THEN** each such record SHALL increment the project's 7-day message count by 1

#### Scenario: Parse assistant tool calls
- **WHEN** a JSONL file contains records with `"type": "assistant"` and `message.content` includes blocks with `"type": "tool_use"`
- **THEN** each `tool_use` block SHALL increment the project's 7-day tool call count by 1

#### Scenario: Parse token usage from assistant messages
- **WHEN** a JSONL file contains records with `"type": "assistant"` and `message.usage` includes `input_tokens` and `output_tokens`
- **THEN** the system SHALL sum `input_tokens + output_tokens` into the project's 7-day total tokens

#### Scenario: Compute API-equivalent cost per project
- **WHEN** token usage is parsed from an assistant message with a `message.model` field
- **THEN** the system SHALL compute cost using the model pricing heuristic: Opus ($15/$75 per M in/out), Sonnet ($3/$15), Haiku ($1/$5)

#### Scenario: Skip files older than 7 days
- **WHEN** a `.jsonl` file has a modification date older than 7 days
- **THEN** the system SHALL NOT parse that file and SHALL contribute 0 to all 7-day per-project stats

#### Scenario: Graceful handling of malformed JSONL lines
- **WHEN** a JSONL line cannot be decoded or is missing expected fields
- **THEN** the system SHALL skip that line without crashing and continue processing remaining lines

### Requirement: Project table displays 7-day per-project stats
The project breakdown table SHALL display Messages, Tools, Tokens, and Cost columns with real data derived from JSONL parsing when the 7-day filter is active.

#### Scenario: 7-day filter active with parsed data
- **WHEN** the stats detail view is displayed
- **THEN** the project table SHALL show `messages7d`, `toolCalls7d`, formatted `totalTokens7d`, and `costEquiv7d` for each project

#### Scenario: Project with zero activity in 7 days
- **WHEN** a project has no sessions modified in the last 7 days
- **THEN** all 7-day columns SHALL display "-" for that project

#### Scenario: Cost formatting
- **WHEN** a project's 7-day API-equivalent cost is greater than 0
- **THEN** the cost SHALL be formatted as a dollar amount (e.g., "$4.66")

#### Scenario: Token formatting
- **WHEN** a project's 7-day total tokens is greater than 0
- **THEN** the tokens SHALL be formatted using compact notation (e.g., "89M", "4.3M", "788K")
