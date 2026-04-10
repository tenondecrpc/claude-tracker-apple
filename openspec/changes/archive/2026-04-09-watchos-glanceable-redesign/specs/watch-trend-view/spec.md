## ADDED Requirements

### Requirement: 7-day horizontal bar chart
The Trend view SHALL display a horizontal row of 7 vertical bars representing the last 7 days of `utilization5h` values from `usageHistory`. Each bar height SHALL be proportional to the utilization value (0.0 = no height, 1.0 = max height). Bars SHALL use `RoundedRectangle(cornerRadius: 3)` shape.

#### Scenario: 7 days of data available
- **WHEN** `usageHistory` contains 7 or more snapshots spanning 7 distinct days
- **THEN** 7 bars are rendered, one per day, evenly spaced

#### Scenario: Fewer than 7 days of data
- **WHEN** `usageHistory` contains snapshots for only 3 distinct days
- **THEN** 7 bar slots are rendered; days with no data show an empty bar placeholder at minimum height (2pt)

#### Scenario: No history data
- **WHEN** `usageHistory` is empty
- **THEN** 7 empty placeholder bars are shown with a "No data" caption in `ClaudeCodeTheme.textTertiary`

### Requirement: Today's bar is highlighted
The bar representing today SHALL use `ClaudeCodeTheme.accent` fill color. All other bars SHALL use `ClaudeCodeTheme.textSecondary` with 0.6 opacity.

#### Scenario: Today has data
- **WHEN** today's utilization is 0.65
- **THEN** the rightmost bar is 65% height and uses `ClaudeCodeTheme.accent` color

#### Scenario: Today has no data yet
- **WHEN** today's snapshot is not yet recorded but `usageState.utilization5h` is available
- **THEN** the rightmost bar uses the current `usageState.utilization5h` value with `ClaudeCodeTheme.accent` color

### Requirement: Day-of-week labels below bars
Each bar SHALL have a single-letter day label below it (M, T, W, T, F, S, S) using `.system(.caption2)` font in `ClaudeCodeTheme.textTertiary`. Today's label SHALL use `ClaudeCodeTheme.textPrimary`.

#### Scenario: Labels match calendar days
- **WHEN** today is Wednesday
- **THEN** the 7 labels read (from left to right) for the last 7 days ending on Wednesday, with "W" as the rightmost label in primary color

### Requirement: Daily average reference line
The chart SHALL display a horizontal dashed line at the average utilization level across the 7 days. The line SHALL use `ClaudeCodeTheme.textTertiary` with 0.5 opacity and 1pt width.

#### Scenario: Average at 45%
- **WHEN** the average of all 7 days' utilization is 0.45
- **THEN** a dashed horizontal line is drawn at 45% of the chart height

#### Scenario: No data for average
- **WHEN** `usageHistory` is empty
- **THEN** no average line is displayed

### Requirement: Summary stats above chart
The view SHALL display two key metrics above the bar chart: "Avg" with the 7-day average utilization as a percentage, and "Peak" with the highest single-day utilization. Both SHALL use `.system(.caption, design: .rounded)` font.

#### Scenario: Stats populated
- **WHEN** 7-day average utilization is 0.45 and peak is 0.82
- **THEN** "Avg 45%" and "Peak 82%" are displayed above the chart

### Requirement: Extra-usage indicator on bars
Bars for days where `isUsingExtraUsage5h` was true SHALL display a small dot above the bar using `ClaudeCodeTheme.info` color to indicate extra usage was consumed that day.

#### Scenario: Extra usage on a day
- **WHEN** a day's snapshot has `isUsingExtraUsage5h == true`
- **THEN** a small blue dot appears above that day's bar
