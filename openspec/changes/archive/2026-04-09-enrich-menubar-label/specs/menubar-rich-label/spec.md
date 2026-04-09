## ADDED Requirements

### Requirement: Menu bar label displays 5-hour utilization percentage segment
When `show5hPercentage` is enabled and usage data is available, the menu bar label SHALL display the 5-hour utilization as an integer percentage (e.g., "42%").

#### Scenario: 5h percentage shown
- **WHEN** `show5hPercentage` is true and `utilization5h = 0.42`
- **THEN** the menu bar label includes "42%"

#### Scenario: 5h percentage disabled
- **WHEN** `show5hPercentage` is false
- **THEN** the 5h percentage segment is omitted

### Requirement: Menu bar label displays 5-hour reset time segment
When `show5hResetTime` is enabled, the menu bar label SHALL display the clock time at which the 5-hour window resets, formatted according to the 24-Hour Time preference (e.g., "8:15p" in 12h mode or "20:15" in 24h mode). The reset time appears immediately after the 5h percentage (no separator within the group).

#### Scenario: 5h reset time in 12-hour format
- **WHEN** `show5hResetTime` is true and `resetAt5h` corresponds to 8:15 PM and 24-hour time is disabled
- **THEN** the label includes "8:15p"

#### Scenario: 5h reset time in 24-hour format
- **WHEN** `show5hResetTime` is true and `resetAt5h` corresponds to 20:15 and 24-hour time is enabled
- **THEN** the label includes "20:15"

#### Scenario: 5h reset time without percentage
- **WHEN** `show5hResetTime` is true and `show5hPercentage` is false
- **THEN** the label shows only the reset time for the 5h group (e.g., "8:15p")

#### Scenario: 5h reset time disabled
- **WHEN** `show5hResetTime` is false
- **THEN** the reset time segment is omitted from the 5h group

### Requirement: Menu bar label displays 7-day utilization percentage segment
When `show7dPercentage` is enabled, the menu bar label SHALL display the 7-day utilization as an integer percentage (e.g., "18%"). The 7-day group is separated from the 5-hour group by ` · `.

#### Scenario: 7d percentage shown
- **WHEN** `show7dPercentage` is true and `utilization7d = 0.18`
- **THEN** the menu bar label includes "18%" in the 7d group

#### Scenario: 7d percentage disabled
- **WHEN** `show7dPercentage` is false
- **THEN** the 7d percentage segment is omitted

### Requirement: Menu bar label displays 7-day reset time segment
When `show7dResetTime` is enabled, the menu bar label SHALL display the clock time at which the 7-day window resets, formatted according to the 24-Hour Time preference. The reset time appears immediately after the 7d percentage (no separator within the group).

#### Scenario: 7d reset time shown
- **WHEN** `show7dResetTime` is true and `resetAt7d` corresponds to 3:42 PM and 24-hour time is disabled
- **THEN** the label includes "3:42p" in the 7d group

#### Scenario: 7d reset time disabled
- **WHEN** `show7dResetTime` is false
- **THEN** the 7d reset time segment is omitted

### Requirement: Menu bar label displays extra usage credits segment
When `showExtraUsageCredits` is enabled and `isUsingExtraUsage` is true, the menu bar label SHALL display used credits and monthly limit (e.g., "$3.20/$20") as the last segment, separated from previous groups by ` · `.

#### Scenario: Extra usage active and toggle enabled
- **WHEN** `showExtraUsageCredits` is true and `isUsingExtraUsage` is true and `usedCreditsAmount = 3.20` and `monthlyLimitAmount = 20.00`
- **THEN** the label includes "$3.20/$20" as the final segment

#### Scenario: Extra usage not active
- **WHEN** `isUsingExtraUsage` is false regardless of toggle state
- **THEN** the extra usage credits segment is not shown

#### Scenario: Extra usage toggle disabled
- **WHEN** `showExtraUsageCredits` is false and `isUsingExtraUsage` is true
- **THEN** the extra usage credits segment is not shown

### Requirement: Groups are separated by middle dot, segments within a group have no separator
The 5h group, 7d group, and extra usage segment SHALL be separated by ` · ` (space, middle dot, space). Within a group, percentage and reset time appear adjacent with only a space. No separator appears before the first group or after the last.

#### Scenario: All segments enabled
- **WHEN** all five toggles are enabled and extra usage is active
- **THEN** the label renders as `42% 8:15p · 18% 3:42p · $3.20/$20`

#### Scenario: Both groups without extra usage
- **WHEN** 5h and 7d toggles are enabled, extra usage is inactive
- **THEN** the label renders as `42% 8:15p · 18% 3:42p`

#### Scenario: Only 5h percentage
- **WHEN** only `show5hPercentage` is true
- **THEN** the label renders as `42%`

#### Scenario: No segments enabled
- **WHEN** all toggles are false
- **THEN** only the pulse dot icon is shown with no text

### Requirement: All menu bar label toggles default to off
All five label segment toggles SHALL default to `false`. On first launch the menu bar shows only the pulse dot icon.

#### Scenario: Fresh install
- **WHEN** the app launches for the first time
- **THEN** no text segments are displayed in the menu bar label
