import Foundation
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - SelectAccountIntent
//
// Widget configuration intent that lets a user pin an iOS or macOS widget to
// a specific Anthropic `accountId`. Leaving `account` unset means "follow the
// iPhone or Mac active account", which is the default rendering behavior for
// a freshly added widget.
//
// Shared between the iOS and macOS widget extensions so both platforms use
// the same parameter shape, entity type, and query logic. The watch widget
// does not use this intent (see task 8.5).
//
// Requires iOS 17 / macOS 14 AppIntents. Deployment targets are currently
// iOS 26 / macOS 26 so this is safely available everywhere this file is
// compiled.

#if canImport(AppIntents) && canImport(WidgetKit)

@available(iOS 17.0, macOS 14.0, *)
struct SelectAccountIntent: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Account"
    static var description = IntentDescription(
        "Choose which Anthropic account this widget displays. Leave empty to follow the active account."
    )

    /// Optional by design: `nil` means "render the currently active account's
    /// snapshot" (the default for a freshly added widget). A non-nil value
    /// pins the widget to that specific accountId, matching the behavior
    /// described in the multi-account-support design document under "Widget
    /// strategy".
    @Parameter(title: "Account")
    var account: AccountEntity?

    init() {}

    init(account: AccountEntity?) {
        self.account = account
    }
}

// MARK: - AccountEntity

/// App Intent entity describing a known Anthropic account eligible for the
/// widget's account picker. `id` is the canonical `accountId` (see
/// `AccountIdentifier`); providers read snapshots by this id directly.
@available(iOS 17.0, macOS 14.0, *)
struct AccountEntity: AppEntity, Identifiable, Hashable {
    /// Canonical accountId (lowercased, NFC-normalized email or CLI-fallback
    /// id). Persisted verbatim inside the intent configuration so later
    /// renders can look up per-account snapshots by the same key.
    let id: String

    /// Human-readable label shown in the account picker. Today this is the
    /// canonical accountId itself (which is usually the email); the host
    /// apps will swap in display names in a future task. Snapshot-level
    /// labeling inside the widget view comes from `WidgetUsageSnapshot.accountLabel`
    /// rather than from this entity.
    let label: String

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Account")
    }

    static var defaultQuery = AccountEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(label)")
    }
}

// MARK: - AccountEntityQuery

/// EntityQuery that enumerates the accountIds the current widget extension
/// can render. Shared by the iOS and macOS widget targets; the platform
/// branching below picks the right `TempoWidgetPlatform` so the query reads
/// from the correct App Group store.
///
/// Results are sourced from `TempoWidgetSnapshotStore.knownAccountIds(platform:)`,
/// which in turn reflects whatever snapshots the host app has written into
/// the shared group container. Accounts without a snapshot yet will not
/// appear until the host refreshes them (matching the existing
/// `read(platform:)` contract: no snapshot, no render).
@available(iOS 17.0, macOS 14.0, *)
struct AccountEntityQuery: EntityQuery {
    init() {}

    /// Look up entities by id. Only known accountIds (those that currently
    /// have a snapshot on disk) are resolved. An unknown id resolves to
    /// nothing so the intent UI treats a previously-pinned-then-removed
    /// account as cleared, letting the provider fall back to the active
    /// account. Task 8.3 layers the user-facing "account removed" indicator
    /// on top of that fallback.
    func entities(for identifiers: [AccountEntity.ID]) async throws -> [AccountEntity] {
        let known = Set(Self.knownAccountIdsForCurrentPlatform())
        return identifiers
            .filter { known.contains($0) }
            .map { AccountEntity(id: $0, label: $0) }
    }

    /// Suggestions shown in the widget configuration picker. Returned in
    /// whatever order `knownAccountIds` produces; callers of the underlying
    /// store preserve filesystem order, which is stable enough for the
    /// picker.
    func suggestedEntities() async throws -> [AccountEntity] {
        Self.knownAccountIdsForCurrentPlatform().map { AccountEntity(id: $0, label: $0) }
    }

    private static func knownAccountIdsForCurrentPlatform() -> [String] {
        #if os(iOS)
        return TempoWidgetSnapshotStore.knownAccountIds(platform: .iOS)
        #elseif os(macOS)
        return TempoWidgetSnapshotStore.knownAccountIds(platform: .macOS)
        #else
        return []
        #endif
    }
}

#endif
