## MODIFIED Requirements

### Requirement: Menu bar percentage text visibility follows user preference
The menu bar item SHALL support five independent label segment toggles: `show5hPercentage`, `show5hResetTime`, `show7dPercentage`, `show7dResetTime`, and `showExtraUsageCredits`. The existing `showPercentageInMenuBar` preference is replaced by `show5hPercentage`. All toggles default to off. Segments render according to the `menubar-rich-label` spec.

#### Scenario: No segments enabled (default)
- **WHEN** all label segment toggles are false
- **THEN** the menu bar item displays the pulse dot icon only with no text

#### Scenario: Mixed segments enabled
- **WHEN** `show5hPercentage` and `show7dPercentage` are true but reset time toggles are false
- **THEN** the menu bar label shows `42% · 18%`
