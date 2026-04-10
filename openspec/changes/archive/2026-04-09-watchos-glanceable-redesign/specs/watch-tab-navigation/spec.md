## ADDED Requirements

### Requirement: Vertical-page TabView with Digital Crown navigation
The watch app SHALL use a `TabView` with `.tabViewStyle(.verticalPage)` as the root container, presenting exactly 3 pages in this order: Dashboard (page 0), Trend (page 1), Session (page 2). The user SHALL navigate between pages by rotating the Digital Crown or swiping vertically.

#### Scenario: App launches on Dashboard page
- **WHEN** the app launches
- **THEN** the Dashboard view is displayed as the first visible page (page 0)

#### Scenario: Digital Crown scrolls to Trend page
- **WHEN** the user rotates the Digital Crown downward from the Dashboard page
- **THEN** the Trend view (page 1) is displayed

#### Scenario: Swipe navigates between pages
- **WHEN** the user swipes up from the Dashboard page
- **THEN** the Trend view (page 1) is displayed

#### Scenario: Page order is fixed
- **WHEN** the user scrolls through all pages
- **THEN** the pages appear in order: Dashboard → Trend → Session

### Requirement: Page indicator dots
The TabView SHALL display page indicator dots to communicate the user's position within the 3-page stack. The dots SHALL follow the system default styling (white dots on dark background).

#### Scenario: Dots reflect current page
- **WHEN** the user is on page 1 (Trend)
- **THEN** the second dot is highlighted and the first and third dots are dimmed

### Requirement: Completion sheet overlays any page
The session completion sheet (`CompletionView`) SHALL present as a `.sheet` overlay regardless of which TabView page is currently active. The sheet SHALL be driven by `store.pendingCompletion` as it is today.

#### Scenario: Completion triggers on Trend page
- **WHEN** `store.pendingCompletion` becomes non-nil while the user is on the Trend page
- **THEN** `CompletionView` is presented as a sheet overlay on the current page
