## MODIFIED Requirements

### Requirement: Optional percentage text preserved
The numeric session percentage text and additional label segments SHALL appear to the right of the pulse dot icon when their respective toggles are enabled. The font remains `.system(size: 12, weight: .medium, design: .monospaced)`. The existing `showPercentage` parameter is replaced by the five segment toggles defined in `menubar-rich-label`.

#### Scenario: Multiple segments shown alongside pulse dot
- **WHEN** `show5hPercentage` and `show5hResetTime` are true and `utilization5h = 0.42` with `resetAt5h` at 8:15 PM
- **THEN** the menu bar shows the pulse dot followed by "42% 8:15p"

#### Scenario: No segments enabled
- **WHEN** all segment toggles are false
- **THEN** the menu bar shows only the pulse dot icon
