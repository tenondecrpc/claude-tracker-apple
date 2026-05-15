import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - TempoWidgetPlatform

enum TempoWidgetPlatform {
    case iOS
    case macOS

    var appGroupIdentifier: String {
        switch self {
        case .iOS:
            "group.com.tenondev.tempo.claude.ioswidget"
        case .macOS:
            "group.com.tenondev.tempo.claude.macwidget"
        }
    }

    fileprivate var widgetKinds: [String] {
        switch self {
        case .iOS:
            TempoWidgetKind.iOSAll
        case .macOS:
            TempoWidgetKind.macOSAll
        }
    }
}

// MARK: - TempoWidgetKind

enum TempoWidgetKind {
    static let iOSRing = "TempoIOSRingWidget"
    static let iOSSummary = "TempoIOSSummaryWidget"
    static let iOSCompact = "TempoIOSCompactWidget"

    static let macOSRing = "TempoMacRingWidget"
    static let macOSSummary = "TempoMacSummaryWidget"
    static let macOSCompact = "TempoMacCompactWidget"

    static let iOSAll = [iOSRing, iOSSummary, iOSCompact]
    static let macOSAll = [macOSRing, macOSSummary, macOSCompact]
}

// MARK: - WidgetUsageSnapshot

/// Current widget snapshot schema version. Bumped to `3` for the
/// multi-account layout where `accountId` and `accountLabel` are first-class
/// required fields. No tolerance for older schema versions is provided:
/// decoding a payload that is missing `accountId` or `accountLabel` MUST
/// throw, matching the "no support for older schema versions" contract in
/// `multi-account-support/design.md`.
private let kWidgetUsageSnapshotSchemaVersion = 3

struct WidgetUsageSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    /// Canonical `accountId` (see `AccountIdentifier`) of the Anthropic
    /// account this snapshot represents. Required on decoding: a stored
    /// snapshot that lacks this key MUST fail to decode rather than
    /// silently defaulting.
    let accountId: String
    /// Human-readable label for the account (typically the email address or
    /// a user-set display name). Required on decoding: a stored snapshot
    /// that lacks this key MUST fail to decode rather than silently
    /// defaulting.
    let accountLabel: String
    let utilization5h: Double
    let utilization7d: Double
    let resetAt5h: Date
    let resetAt7d: Date
    let isMocked: Bool
    let isDoubleLimitPromoActive: Bool
    let extraUsageEnabled: Bool
    let extraUsageUsedAmountUSD: Double?
    let extraUsageLimitAmountUSD: Double?
    let extraUsageUtilizationPercent: Double?
    let appearanceModeRawValue: String?

    var appearanceMode: AppearanceMode {
        appearanceModeRawValue.flatMap(AppearanceMode.init(rawValue:)) ?? .dark
    }

    /// Build a snapshot from a freshly computed `UsageState`. `accountId`
    /// is sourced from the usage state itself so callers cannot silently
    /// target a different account than the usage payload belongs to.
    /// `accountLabel` is required because widgets must have a clear account
    /// identity to render in their header.
    init(
        usage: UsageState,
        updatedAt: Date,
        accountLabel: String,
        appearanceMode: AppearanceMode = .dark
    ) {
        schemaVersion = kWidgetUsageSnapshotSchemaVersion
        self.updatedAt = updatedAt
        accountId = usage.accountId
        self.accountLabel = accountLabel
        utilization5h = usage.utilization5h
        utilization7d = usage.utilization7d
        resetAt5h = usage.resetAt5h
        resetAt7d = usage.resetAt7d
        isMocked = usage.isMocked
        isDoubleLimitPromoActive = usage.isDoubleLimitPromoActive == true
        extraUsageEnabled = usage.extraUsage?.isEnabled == true
        extraUsageUsedAmountUSD = usage.extraUsage?.usedCreditsAmount
        extraUsageLimitAmountUSD = usage.extraUsage?.monthlyLimitAmount
        extraUsageUtilizationPercent = usage.extraUsage?.utilization
        appearanceModeRawValue = appearanceMode.rawValue
    }

    /// Rebuild an existing snapshot with an updated appearance mode. The
    /// account identity (`accountId`, `accountLabel`) is preserved verbatim
    /// from the source snapshot because this initializer only exists to
    /// refresh the appearance, not to retarget the snapshot to a different
    /// account.
    init(snapshot: WidgetUsageSnapshot, appearanceMode: AppearanceMode) {
        schemaVersion = kWidgetUsageSnapshotSchemaVersion
        updatedAt = snapshot.updatedAt
        accountId = snapshot.accountId
        accountLabel = snapshot.accountLabel
        utilization5h = snapshot.utilization5h
        utilization7d = snapshot.utilization7d
        resetAt5h = snapshot.resetAt5h
        resetAt7d = snapshot.resetAt7d
        isMocked = snapshot.isMocked
        isDoubleLimitPromoActive = snapshot.isDoubleLimitPromoActive
        extraUsageEnabled = snapshot.extraUsageEnabled
        extraUsageUsedAmountUSD = snapshot.extraUsageUsedAmountUSD
        extraUsageLimitAmountUSD = snapshot.extraUsageLimitAmountUSD
        extraUsageUtilizationPercent = snapshot.extraUsageUtilizationPercent
        appearanceModeRawValue = appearanceMode.rawValue
    }

    var hasExtraUsageSummary: Bool {
        extraUsageEnabled && extraUsageUsedAmountUSD != nil && extraUsageLimitAmountUSD != nil
    }
}

// MARK: - WidgetFreshnessState

enum WidgetFreshnessState: Equatable {
    case fresh
    case stale(since: Date)
}

enum WidgetFreshnessPolicy {
    static let staleThreshold: TimeInterval = 35 * 60

    static func status(updatedAt: Date, now: Date = Date()) -> WidgetFreshnessState {
        now.timeIntervalSince(updatedAt) > staleThreshold
            ? .stale(since: updatedAt)
            : .fresh
    }
}

enum WidgetTimelineRefreshPolicy {
    static let missingSnapshotRetryInterval: TimeInterval = 60
    static let freshSnapshotRefreshInterval: TimeInterval = 5 * 60
    static let staleSnapshotRefreshInterval: TimeInterval = 15 * 60

    static func nextRefreshDate(snapshot: WidgetUsageSnapshot?, now: Date = Date()) -> Date {
        guard let snapshot else {
            return now.addingTimeInterval(missingSnapshotRetryInterval)
        }

        switch WidgetFreshnessPolicy.status(updatedAt: snapshot.updatedAt, now: now) {
        case .fresh:
            let nextPeriodicRefresh = now.addingTimeInterval(freshSnapshotRefreshInterval)
            let staleAt = snapshot.updatedAt.addingTimeInterval(WidgetFreshnessPolicy.staleThreshold)
            let nextRefresh = min(nextPeriodicRefresh, staleAt)
            return max(now.addingTimeInterval(missingSnapshotRetryInterval), nextRefresh)
        case .stale:
            return now.addingTimeInterval(staleSnapshotRefreshInterval)
        }
    }
}

// MARK: - TempoWidgetSnapshotStore

/// Pointer file body describing which accountId widgets should render when
/// a provider has no explicit account selection. Written by the host apps
/// after a poll lands or after the user changes the active account; read
/// by `TempoWidgetSnapshotStore.read(platform:)`.
///
/// The pointer is intentionally separate from any per-account
/// `WidgetUsageSnapshot` so that updating the active selection does not
/// require rewriting or copying a snapshot payload.
private struct TempoActiveAccountPointer: Codable {
    let activeAccountId: String?
}

/// Shared-App-Group storage for per-account widget snapshots plus the
/// "which account is active" pointer consumed by the widget extensions.
///
/// Layout under the App Group container (or the
/// `TEMPO_WIDGET_SNAPSHOT_OVERRIDE_DIR` root during tests):
///
/// - `Library/Application Support/Tempo/accounts/<percentEncodedAccountId>/tempo.widget.snapshot.json`
///   - One snapshot file per known account. `percentEncodedAccountId` is
///     produced by `AccountIdentifier.percentEncodedDirectoryName(for:)` so
///     the in-memory accountId stays canonical while the directory name
///     stays filesystem-safe.
/// - `Library/Application Support/Tempo/active-account.json`
///   - Pointer file (`TempoActiveAccountPointer`) identifying which
///     accountId the default (no-intent) widgets should render. Missing or
///     empty pointer means "no active account".
///
/// No migration is performed from the pre-multi-account layout
/// (`Library/Application Support/tempo.widget.snapshot.json`); see
/// `multi-account-support/design.md` -> "No migration, no fallback". Stale
/// files from prior dev builds may linger in the App Group container and
/// can be deleted by hand.
enum TempoWidgetSnapshotStore {
    /// Snapshot filename inside each per-account directory. Kept from the
    /// previous layout so widget code continues to reference the same
    /// constant even though the containing path is now per-account.
    private static let snapshotFilename = "tempo.widget.snapshot.json"

    /// Pointer filename, one per platform App Group.
    private static let activeAccountPointerFilename = "active-account.json"

    /// Root subdirectory under `Library/Application Support` that contains
    /// the per-account tree and the pointer. Nesting under `Tempo/` keeps
    /// our files from colliding with any other App Group consumers.
    private static let rootSubdirectoryName = "Tempo"

    /// Subdirectory that holds one directory per known account.
    private static let accountsDirectoryName = "accounts"

    /// Environment key used by the widget smoke test and future tests to
    /// redirect the root directory to a temporary location. When set, the
    /// override directory replaces the App Group root entirely, so
    /// `accounts/` and the pointer live directly underneath it.
    private static let overrideDirectoryEnvironmentKey = "TEMPO_WIDGET_SNAPSHOT_OVERRIDE_DIR"

    // MARK: Reads

    /// Reads the snapshot for the currently active account, as indicated by
    /// the pointer file. Returns `nil` when no pointer is present, when the
    /// pointer names an accountId whose snapshot has not been written, or
    /// when decoding fails (for example, a stale schema version).
    ///
    /// Widget providers use this variant when they render the default "no
    /// intent configured" surface. Providers that carry an explicit
    /// accountId (via `SelectAccountIntent` in task 8.2) should call
    /// `read(accountId:platform:)` instead.
    static func read(platform: TempoWidgetPlatform) -> WidgetUsageSnapshot? {
        guard let activeAccountId = readActiveAccountId(platform: platform),
              !activeAccountId.isEmpty else {
            return nil
        }
        return read(accountId: activeAccountId, platform: platform)
    }

    /// Reads a specific account's snapshot from its per-account slot.
    /// Returns `nil` when no snapshot exists yet or decoding fails.
    static func read(accountId: String, platform: TempoWidgetPlatform) -> WidgetUsageSnapshot? {
        guard !accountId.isEmpty,
              let snapshotURL = snapshotURL(accountId: accountId, platform: platform),
              let data = try? Data(contentsOf: snapshotURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetUsageSnapshot.self, from: data)
    }

    /// Returns the accountId stored in the pointer file, or `nil` when the
    /// pointer is absent, malformed, or explicitly cleared.
    static func readActiveAccountId(platform: TempoWidgetPlatform) -> String? {
        guard let pointerURL = activeAccountPointerURL(for: platform),
              let data = try? Data(contentsOf: pointerURL) else {
            return nil
        }
        let decoder = JSONDecoder()
        let pointer = try? decoder.decode(TempoActiveAccountPointer.self, from: data)
        guard let id = pointer?.activeAccountId, !id.isEmpty else { return nil }
        return id
    }

    /// Enumerates the accountIds that currently have a snapshot written to
    /// disk. Used by `SelectAccountIntent` suggestions (task 8.2) and the
    /// widget smoke test. Results are canonical accountIds (percent-decoded
    /// from their on-disk directory names), returned in filesystem order.
    /// Account directories without a snapshot file are ignored so the
    /// caller always gets a set the widgets can actually render.
    static func knownAccountIds(platform: TempoWidgetPlatform) -> [String] {
        guard let accountsDirectory = accountsDirectoryURL(for: platform),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: accountsDirectory,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        return entries.compactMap { url -> String? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                return nil
            }

            let snapshotPath = url.appendingPathComponent(snapshotFilename).path
            guard FileManager.default.fileExists(atPath: snapshotPath) else { return nil }

            // The directory name is the percent-encoded form of the canonical
            // accountId. Decode back to canonical so callers never see the
            // filesystem-safe form.
            let directoryName = url.lastPathComponent
            return directoryName.removingPercentEncoding ?? directoryName
        }
    }

    // MARK: Writes

    /// Writes a snapshot to the per-account slot derived from
    /// `snapshot.accountId`. Does NOT update the active-account pointer;
    /// callers use `write(activeAccountId:platform:)` to control the
    /// pointer explicitly so that a non-active-account poll can refresh
    /// its own snapshot without retargeting the default widgets.
    @discardableResult
    static func write(_ snapshot: WidgetUsageSnapshot, platform: TempoWidgetPlatform) -> Bool {
        guard !snapshot.accountId.isEmpty,
              let snapshotURL = snapshotURL(accountId: snapshot.accountId, platform: platform) else {
            DevLog.trace(
                "AuthTrace",
                "Widget snapshot write skipped platform=\(platform.debugName) accountId=\(snapshot.accountId) reason=no-url"
            )
            return false
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(snapshot) else {
            DevLog.trace(
                "AuthTrace",
                "Widget snapshot write skipped platform=\(platform.debugName) accountId=\(snapshot.accountId) reason=encode-failed"
            )
            return false
        }

        do {
            let directory = snapshotURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: snapshotURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
            DevLog.trace(
                "AuthTrace",
                "Widget snapshot wrote platform=\(platform.debugName) path=\(snapshotURL.path) accountId=\(snapshot.accountId) updatedAt=\(snapshot.updatedAt)"
            )
            return true
        } catch {
            DevLog.trace(
                "AuthTrace",
                "Widget snapshot write failed platform=\(platform.debugName) accountId=\(snapshot.accountId) error=\(error.localizedDescription)"
            )
            return false
        }
    }

    /// Updates the active-account pointer. Passing `nil` removes the
    /// pointer file so subsequent `read(platform:)` calls return `nil` and
    /// the default widgets render their "no active account" state.
    /// Updates the active-account pointer. Passing `nil` removes the
    /// pointer file so subsequent `read(platform:)` calls return `nil` and
    /// the default widgets render their "no active account" state.
    ///
    /// The pointer is intentionally decoupled from snapshot writes so the
    /// host apps can:
    /// 1. Refresh a non-active account's snapshot on poll without flipping
    ///    which account the widgets render.
    /// 2. Flip which account the widgets render (user changed the active
    ///    selection) without needing to rewrite an otherwise-unchanged
    ///    snapshot.
    @discardableResult
    static func write(activeAccountId: String?, platform: TempoWidgetPlatform) -> Bool {
        guard let pointerURL = activeAccountPointerURL(for: platform) else {
            DevLog.trace(
                "AuthTrace",
                "Widget active pointer write skipped platform=\(platform.debugName) accountId=\(activeAccountId ?? "nil") reason=no-url"
            )
            return false
        }

        // `nil` or empty clears the pointer. Remove the file rather than
        // writing a placeholder so `readActiveAccountId(platform:)` can
        // treat "missing file" and "explicitly cleared" the same way.
        let normalizedId = activeAccountId.flatMap { $0.isEmpty ? nil : $0 }
        if normalizedId == nil {
            do {
                if FileManager.default.fileExists(atPath: pointerURL.path) {
                    try FileManager.default.removeItem(at: pointerURL)
                }
                DevLog.trace(
                    "AuthTrace",
                    "Widget active pointer cleared platform=\(platform.debugName) path=\(pointerURL.path)"
                )
                return true
            } catch {
                DevLog.trace(
                    "AuthTrace",
                    "Widget active pointer clear failed platform=\(platform.debugName) error=\(error.localizedDescription)"
                )
                return false
            }
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(TempoActiveAccountPointer(activeAccountId: normalizedId)) else {
            DevLog.trace(
                "AuthTrace",
                "Widget active pointer write skipped platform=\(platform.debugName) accountId=\(normalizedId ?? "nil") reason=encode-failed"
            )
            return false
        }

        do {
            let directory = pointerURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: pointerURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pointerURL.path)
            DevLog.trace(
                "AuthTrace",
                "Widget active pointer wrote platform=\(platform.debugName) path=\(pointerURL.path) accountId=\(normalizedId ?? "nil")"
            )
            return true
        } catch {
            DevLog.trace(
                "AuthTrace",
                "Widget active pointer write failed platform=\(platform.debugName) accountId=\(normalizedId ?? "nil") error=\(error.localizedDescription)"
            )
            return false
        }
    }

    /// Removes the per-account widget snapshot directory and clears the
    /// active-account pointer when it still references the deleted
    /// account. Used by sign-out / account-removal flows to keep the App
    /// Group container in lockstep with the registry, and by a one-shot
    /// startup sweep that removes orphans left behind by previous builds
    /// or aborted sign-outs.
    ///
    /// Returns `true` when at least one filesystem mutation succeeded
    /// (snapshot directory removed, pointer cleared, or both). Missing
    /// directories are not failures; the function is intentionally
    /// idempotent so repeat calls with the same `accountId` are safe.
    @discardableResult
    static func delete(accountId: String, platform: TempoWidgetPlatform) -> Bool {
        guard !accountId.isEmpty else { return false }

        var didMutate = false

        if let directoryURL = accountDirectoryURL(accountId: accountId, platform: platform),
           FileManager.default.fileExists(atPath: directoryURL.path) {
            do {
                try FileManager.default.removeItem(at: directoryURL)
                didMutate = true
                DevLog.trace(
                    "AuthTrace",
                    "Widget snapshot directory removed platform=\(platform.debugName) path=\(directoryURL.path) accountId=\(accountId)"
                )
            } catch {
                DevLog.trace(
                    "AuthTrace",
                    "Widget snapshot directory removal failed platform=\(platform.debugName) accountId=\(accountId) error=\(error.localizedDescription)"
                )
            }
        }

        if readActiveAccountId(platform: platform) == accountId {
            if write(activeAccountId: nil, platform: platform) {
                didMutate = true
            }
        }

        return didMutate
    }

    /// Removes per-account snapshot directories whose accountIds are NOT
    /// in `keepAccountIds`. Idempotent and safe to call on every cold
    /// launch; legacy accounts or sign-outs that did not propagate here
    /// (older builds, manual deletions of the registry, abandoned demo
    /// sessions) are cleaned up so the widget store stays in lockstep
    /// with the registry.
    ///
    /// The pointer file is preserved unless it currently references an
    /// accountId not in `keepAccountIds`, in which case it is cleared so
    /// the default widgets fall back to their "no active account" state
    /// instead of silently flipping to whatever directory still happens
    /// to exist.
    @discardableResult
    static func reconcile(keepAccountIds: Set<String>, platform: TempoWidgetPlatform) -> Int {
        guard let accountsDirectory = accountsDirectoryURL(for: platform),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: accountsDirectory,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return 0
        }

        var removed = 0
        for url in entries {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            let directoryName = url.lastPathComponent
            let canonicalAccountId = directoryName.removingPercentEncoding ?? directoryName

            if keepAccountIds.contains(canonicalAccountId) { continue }

            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
                DevLog.trace(
                    "AuthTrace",
                    "Widget snapshot orphan removed platform=\(platform.debugName) path=\(url.path) accountId=\(canonicalAccountId)"
                )
            } catch {
                DevLog.trace(
                    "AuthTrace",
                    "Widget snapshot orphan removal failed platform=\(platform.debugName) path=\(url.path) error=\(error.localizedDescription)"
                )
            }
        }

        if let pointerAccountId = readActiveAccountId(platform: platform),
           !keepAccountIds.contains(pointerAccountId) {
            if write(activeAccountId: nil, platform: platform) {
                DevLog.trace(
                    "AuthTrace",
                    "Widget active pointer cleared during reconcile platform=\(platform.debugName) staleAccountId=\(pointerAccountId)"
                )
            }
        }

        return removed
    }

    // MARK: URL helpers

    /// Returns the root directory that contains the per-account tree and
    /// the pointer file. When the override env is set, the override dir
    /// IS this root (everything nests beneath it). Otherwise the root is
    /// the App Group container's `Library/Application Support/Tempo/`
    /// subdirectory.
    private static func rootDirectoryURL(for platform: TempoWidgetPlatform) -> URL? {
        if let overridePath = ProcessInfo.processInfo.environment[overrideDirectoryEnvironmentKey],
           !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
        }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: platform.appGroupIdentifier
        ) else {
            return nil
        }

        return containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(rootSubdirectoryName, isDirectory: true)
    }

    private static func accountsDirectoryURL(for platform: TempoWidgetPlatform) -> URL? {
        rootDirectoryURL(for: platform)?
            .appendingPathComponent(accountsDirectoryName, isDirectory: true)
    }

    private static func accountDirectoryURL(accountId: String, platform: TempoWidgetPlatform) -> URL? {
        let encoded = AccountIdentifier.percentEncodedDirectoryName(for: accountId)
        return accountsDirectoryURL(for: platform)?
            .appendingPathComponent(encoded, isDirectory: true)
    }

    private static func snapshotURL(accountId: String, platform: TempoWidgetPlatform) -> URL? {
        accountDirectoryURL(accountId: accountId, platform: platform)?
            .appendingPathComponent(snapshotFilename)
    }

    private static func activeAccountPointerURL(for platform: TempoWidgetPlatform) -> URL? {
        rootDirectoryURL(for: platform)?
            .appendingPathComponent(activeAccountPointerFilename)
    }

    #if canImport(WidgetKit)
    static func reloadTimelines(for platform: TempoWidgetPlatform) {
        for kind in platform.widgetKinds {
            DevLog.trace(
                "AuthTrace",
                "Widget timeline reload requested platform=\(platform.debugName) kind=\(kind)"
            )
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
    #endif
}

private extension TempoWidgetPlatform {
    var debugName: String {
        switch self {
        case .iOS:
            "iOS"
        case .macOS:
            "macOS"
        }
    }
}
