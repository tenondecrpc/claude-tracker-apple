## MODIFIED Requirements

### Requirement: Widgets render from per-account widget snapshots
Tempo widgets SHALL render from per-account snapshots stored in shared App Group storage. Each snapshot SHALL be tagged with its `accountId`. The storage scheme SHALL support multiple snapshots simultaneously (one per account). Widgets SHALL NOT read directly from the Anthropic API, iCloud documents, or `NSMetadataQuery`.

A widget without an explicit account configuration SHALL render the snapshot for the locally active accountId (macOS and iOS widgets follow their host platform's active account selection). A widget configured with an `AccountIntent` SHALL render the snapshot for the configured accountId.

#### Scenario: Default widget follows active account
- **WHEN** a user adds a Tempo widget with no account configuration on iOS and the iPhone has active account A
- **THEN** the widget renders account A's latest snapshot and updates when the active account changes

#### Scenario: Configured widget follows fixed account
- **WHEN** a user adds a Tempo widget and configures it for account B via the account intent
- **THEN** the widget renders account B's snapshot regardless of which account is active on the host

#### Scenario: No direct sync work in widget extension
- **WHEN** the widget extension renders content
- **THEN** it uses only the shared per-account snapshot and local placeholder data, without starting its own network or iCloud read flow

### Requirement: Account configuration intent on iOS and macOS widgets
Tempo SHALL provide an `SelectAccountIntent` (WidgetKit AppIntent) on iOS and macOS widgets. The intent SHALL dynamically list accountIds from `Tempo/accounts/index.json` plus an "Active account" entry. The default selection SHALL be "Active account".

watchOS widgets SHALL NOT expose this intent; the watch always renders the iPhone's active account.

#### Scenario: Intent lists known accounts
- **WHEN** a user configures a Tempo widget on iOS and opens the account picker
- **THEN** the picker shows "Active account" plus every accountId currently present in `index.json`

#### Scenario: Intent default is Active account
- **WHEN** a widget is first added without explicit configuration
- **THEN** its account selection defaults to "Active account"

#### Scenario: watch widget has no account intent
- **WHEN** a user configures a Tempo watch widget
- **THEN** no account selector is presented and the widget renders the iPhone's active account

### Requirement: Missing or removed account falls back gracefully
If a widget's configured accountId no longer exists in the registry (removed, migrated, or never present), the widget SHALL fall back to rendering the active account's snapshot and SHALL display a small badge or footer indicating that the pinned account is unavailable.

#### Scenario: Pinned account removed
- **WHEN** a widget is configured for accountId C and C is later removed from the registry
- **THEN** the widget renders the active account's snapshot and shows an "account removed" indicator

#### Scenario: No snapshot available for configured account
- **WHEN** a widget's configured accountId exists but has no snapshot yet (e.g., first poll still pending)
- **THEN** the widget renders a waiting state and does not substitute another account's snapshot silently

### Requirement: Widgets show core Tempo usage metrics per account
Each widget variant SHALL display the target account's latest current-session utilization and weekly utilization from the shared per-account snapshot. Medium and compact widgets SHALL also display reset timing context, and widgets SHALL display extra-usage information when that data is present in the snapshot.

#### Scenario: Summary widget shows both percentages for configured account
- **WHEN** a medium summary widget configured for account A reads a snapshot with `utilization5h = 0.45` and `utilization7d = 0.67`
- **THEN** the widget displays 45% for the current session and 67% for the weekly limit for account A

#### Scenario: Reset timing appears in dense text layouts
- **WHEN** the target account's snapshot includes `resetAt5h` and `resetAt7d`
- **THEN** the medium and compact widgets display reset timing labels for the session and weekly metrics

#### Scenario: Extra usage shown when enabled
- **WHEN** the target account's snapshot includes enabled extra-usage values
- **THEN** at least one widget variant displays the extra-usage summary without hiding the core session and weekly metrics

### Requirement: Widgets include account label in dense layouts
Widget variants that have room for a secondary label SHALL render the account label (display name or email prefix) so users can tell which account they are looking at. The small ring variant MAY omit the label for space reasons but SHALL include it in its accessibility description.

#### Scenario: Medium widget shows account label
- **WHEN** the medium summary widget renders for account A
- **THEN** the account label is visible somewhere in the widget content

#### Scenario: Small widget accessibility
- **WHEN** the small ring widget renders for account A
- **THEN** its accessibility label includes the account label

### Requirement: Widgets expose waiting, stale, and mock states
Tempo widgets SHALL communicate data freshness. If no valid widget snapshot exists for the target account, widgets SHALL render an empty or waiting state. If the target account's snapshot is stale, widgets SHALL show that the data is old. If the target account's snapshot is based on mock data, widgets SHALL visibly indicate mock state.

#### Scenario: Waiting state with no snapshot for account
- **WHEN** the widget provider cannot find a valid widget snapshot for its target accountId
- **THEN** the widget displays a waiting or setup state instead of empty metric placeholders

#### Scenario: Stale state shown
- **WHEN** the widget snapshot for the target account exceeds the app-defined freshness threshold
- **THEN** the widget displays a stale-data indicator or "updated ago" label

#### Scenario: Mock state shown
- **WHEN** the widget snapshot for the target account has `isMocked = true`
- **THEN** the widget shows a visible mock indicator

### Requirement: Widget taps open Tempo to the correct account
Tempo widgets SHALL attach a deep link that opens the host app in a relevant destination scoped to the widget's target account. On iOS the deep link SHALL set the active account to the widget's target account when it differs from the current active; on macOS the detail window SHALL open bound to the target account.

#### Scenario: iOS widget tap opens dashboard for target account
- **WHEN** the user taps an iOS widget whose target is account A
- **THEN** Tempo opens to the dashboard and the active account is set to account A

#### Scenario: macOS widget tap opens detail for target account
- **WHEN** the user taps a macOS widget whose target is account A
- **THEN** Tempo opens the detail window bound to account A

#### Scenario: Widget tap with "Active account" selection
- **WHEN** the user taps a widget configured with "Active account"
- **THEN** Tempo opens to the corresponding destination without changing the active account
