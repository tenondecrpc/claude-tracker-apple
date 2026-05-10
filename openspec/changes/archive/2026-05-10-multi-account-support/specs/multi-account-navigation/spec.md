## ADDED Requirements

### Requirement: macOS menu bar popover exposes account switcher
The macOS menu bar popover SHALL display an Account row at the top when at least one account is registered. The row SHALL show the active account's label (display name or email) and a chevron control that opens an account switcher.

The switcher SHALL list all registered accounts, mark the active one, and SHALL include:
- "Add account" - opens the Welcome window in add-account mode
- "Manage accounts" - opens Preferences on the Accounts pane
- A per-account row action to "Set as active"

Switching the active account SHALL update `AccountRegistry.activeAccountId`, trigger a widget timeline reload, and retarget any open Detail window to the newly active account.

#### Scenario: Active account shown in popover
- **WHEN** the popover opens and the registry has two accounts with one marked active
- **THEN** the active account label is visible at the top and the chevron is enabled

#### Scenario: Switching account from popover
- **WHEN** the user picks "Set as active" for a different account in the switcher
- **THEN** `activeAccountId` is updated, widget timelines are reloaded, and the popover now shows the new active account

#### Scenario: No accounts registered
- **WHEN** the popover opens with zero accounts registered
- **THEN** the Account row is hidden and the existing "Not Signed In" call-to-action is shown

### Requirement: macOS Welcome window supports add-account mode
The Welcome window SHALL support two entry modes: initial sign-in and add-account. In both modes the sign-in button SHALL create a new account in the registry rather than replace the currently active one. The add-account mode SHALL be distinguishable by a header "Add Another Account" and a secondary "Cancel" action that closes the window without affecting existing accounts.

#### Scenario: Sign-in creates a new registry entry
- **WHEN** the user completes OAuth from the Welcome window with at least one account already registered
- **THEN** a new `Account` is added to the registry and the registered list now contains the previous accounts plus the new one

#### Scenario: Sign-in sets the new account as active when first
- **WHEN** the user completes OAuth from the Welcome window and no accounts existed before
- **THEN** the new account is added to the registry and automatically becomes the active account

#### Scenario: Cancel in add-account mode
- **WHEN** the user opens the Welcome window via "Add account" and then cancels
- **THEN** no change is made to the registry and the active account is unchanged

### Requirement: macOS Preferences exposes Accounts pane
The Preferences window SHALL include an Accounts pane that lists every registered account with: label, email, createdAt, last successful poll time, last session ingested timestamp, and a "Sign out" action per row. A "Add account" button SHALL be available at the bottom of the list.

Sign-out from this pane SHALL target the selected account only: it SHALL delete that account's Keychain credential, remove the account from the registry, move its iCloud data under `retired/`, and SHALL NOT affect any other account.

#### Scenario: Accounts list renders per-account metadata
- **WHEN** the Accounts pane opens with two registered accounts
- **THEN** the list shows two rows with each account's label, email, last poll time, and last session time

#### Scenario: Per-account sign-out is scoped
- **WHEN** the user signs out of a specific account from the Accounts pane
- **THEN** only that account's credentials are deleted and only that account is removed from the registry

#### Scenario: Sign-out of active account reassigns active
- **WHEN** the user signs out of the currently active account and at least one other account remains
- **THEN** `activeAccountId` is reassigned to the first remaining account in the list

### Requirement: macOS Detail window follows active account
The Detail window SHALL bind to the active account and its per-account data. When the active account changes, the Detail window SHALL reload usage, history, session, and project views for the new account without requiring a window close/reopen.

The window header SHALL show the active account label so users can identify which account's data is displayed.

#### Scenario: Detail window updates on active change
- **WHEN** the Detail window is open showing account A's data and the user switches active to account B
- **THEN** the window reloads usage rings, history chart, and session list to show account B's data, and the header label updates to B

#### Scenario: Detail window header
- **WHEN** the Detail window opens
- **THEN** the active account label is visible in the header area

### Requirement: iOS dashboard exposes account chip
The iOS dashboard SHALL display an account chip in its header showing the active account label. Tapping the chip SHALL present an Accounts sheet that:
- Lists all registered accounts discovered from iCloud (with label, email, last-updated time)
- Indicates the active account
- Lets the user tap an account to set it as active
- Shows a "Add an account" footer that instructs users to sign in on the Mac app

#### Scenario: Chip shows active account
- **WHEN** the iOS app has discovered two accounts and one is active
- **THEN** the dashboard header chip shows the active account's label

#### Scenario: Selecting an account from the sheet
- **WHEN** the user taps a non-active account in the Accounts sheet
- **THEN** `activeAccountId` is persisted to iOS `UserDefaults`, the dashboard reloads for that account, and a watch relay update fires

#### Scenario: No accounts discovered
- **WHEN** iOS has not discovered any accounts from iCloud
- **THEN** the dashboard shows a "Connect via Mac app" state and no account chip is rendered

### Requirement: iOS Activity and Session views filter by active account
iOS Activity, session history, and detail screens SHALL filter their contents to the currently active accountId. Data from non-active accounts SHALL NOT be mixed into active-account views.

#### Scenario: Activity view filters
- **WHEN** the active account is A and iCloud contains session data for A and B
- **THEN** the Activity view shows only sessions tagged with accountId A

#### Scenario: Switching active account refreshes activity
- **WHEN** the user switches active account from A to B
- **THEN** the Activity view reloads and now shows only sessions tagged with B

### Requirement: Unassigned CLI-only sessions are grouped
When a session is ingested from the local Claude Code database without matching any registered account, it SHALL be tagged with the `unassigned` accountId and surfaced in a dedicated "CLI-only sessions" group in both macOS Detail and iOS Activity surfaces. The UI SHALL offer an "Associate with account" action that lets the user reassign the session to an existing account on macOS.

#### Scenario: Unassigned session displayed in dedicated group
- **WHEN** a session was ingested without a matching accountId
- **THEN** it appears in a "CLI-only sessions" group rather than under any specific account

#### Scenario: Associate with account action on macOS
- **WHEN** the user chooses "Associate with account" for an unassigned session on macOS and selects a target account
- **THEN** the session is retagged with that target accountId and written to that account's `latest.json` and history, and it is removed from the unassigned group

#### Scenario: iOS cannot associate
- **WHEN** the user taps "Associate with account" on iOS
- **THEN** the UI explains that association is available on the Mac app and does not modify state
