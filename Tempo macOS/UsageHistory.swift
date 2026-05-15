import Foundation

// MARK: - UsageSnapshot

struct UsageSnapshot: Codable, Identifiable {
    let id: UUID
    let date: Date
    let utilization5h: Double
    let utilization7d: Double
    let isUsingExtraUsage5h: Bool
    let isUsingExtraUsage7d: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case date
        case utilization5h
        case utilization7d
        case isUsingExtraUsage
        case isUsingExtraUsage5h
        case isUsingExtraUsage7d
    }

    var isUsingExtraUsage: Bool {
        isUsingExtraUsage5h || isUsingExtraUsage7d
    }

    init(
        date: Date,
        utilization5h: Double,
        utilization7d: Double,
        isUsingExtraUsage5h: Bool = false,
        isUsingExtraUsage7d: Bool = false
    ) {
        self.id = UUID()
        self.date = date
        self.utilization5h = utilization5h
        self.utilization7d = utilization7d
        self.isUsingExtraUsage5h = isUsingExtraUsage5h
        self.isUsingExtraUsage7d = isUsingExtraUsage7d
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try container.decode(Date.self, forKey: .date)
        utilization5h = try container.decode(Double.self, forKey: .utilization5h)
        utilization7d = try container.decode(Double.self, forKey: .utilization7d)
        let legacyFlag = try container.decodeIfPresent(Bool.self, forKey: .isUsingExtraUsage) ?? false
        isUsingExtraUsage5h = try container.decodeIfPresent(Bool.self, forKey: .isUsingExtraUsage5h) ?? legacyFlag
        isUsingExtraUsage7d = try container.decodeIfPresent(Bool.self, forKey: .isUsingExtraUsage7d) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(date, forKey: .date)
        try container.encode(utilization5h, forKey: .utilization5h)
        try container.encode(utilization7d, forKey: .utilization7d)
        try container.encode(isUsingExtraUsage5h, forKey: .isUsingExtraUsage5h)
        try container.encode(isUsingExtraUsage7d, forKey: .isUsingExtraUsage7d)
    }
}

// MARK: - UsageHistory
//
// Per-account usage history store. Each Anthropic account has its own
// bucket of `UsageSnapshot`s kept in memory under `histories[accountId]`
// and persisted to its own iCloud file at
// `TempoICloud.usageHistoryFileURL(for: accountId)`.
//
// Multi-account layout (see
// `openspec/changes/multi-account-support/design.md` - "iCloud layout"):
//
// ```
// Tempo/
//   accounts/
//     <accountIdDir>/
//       usage-history.json   <- one per account, each owned by this class
// ```
//
// This class no longer writes to any flat `Tempo/usage-history.json` path
// and no longer reads or writes the legacy
// `~/.config/tempo-for-claude/usage-history.json` cache. The iCloud file
// per account is the single source of truth; in-memory state is seeded by
// `load(for:)` or `loadAll(accountIds:)` and kept in sync by `append`.
//
// Callers decide which account to render (e.g. the coordinator's
// `activeAccountId`) and read via `history(for:)`. The class does not
// track the active account itself, keeping this type a pure per-account
// store.

@Observable
@MainActor
final class UsageHistory {

    /// Per-account in-memory snapshots, keyed by canonical `accountId`
    /// (as produced by `AccountIdentifier.canonicalize(email:)`). Entries
    /// within each bucket are sorted ascending by `date`.
    private(set) var histories: [String: [UsageSnapshot]] = [:]

    private static let maxAge: TimeInterval = 30 * 24 * 3600  // 30 days

    init() {}

    // MARK: - Public API

    /// Returns the in-memory history for `accountId`. Returns an empty
    /// array if the account has not been `load(for:)`ed yet or has no
    /// recorded snapshots.
    func history(for accountId: String) -> [UsageSnapshot] {
        histories[accountId] ?? []
    }

    /// Appends a snapshot derived from `state` into that state's account
    /// bucket (`state.accountId`), prunes entries older than 30 days, and
    /// persists the bucket to the per-account iCloud file. Other accounts'
    /// buckets and files are left untouched.
    func append(usage state: UsageState) {
        let accountId = state.accountId
        let snapshot = UsageSnapshot(
            date: Date(),
            utilization5h: state.utilization5h,
            utilization7d: state.utilization7d,
            isUsingExtraUsage5h: state.isUsingExtraUsage5h,
            isUsingExtraUsage7d: state.isUsingExtraUsage7d
        )
        var bucket = histories[accountId] ?? []
        bucket.append(snapshot)
        histories[accountId] = Self.mergeAndPrune(bucket, with: [], maxAge: Self.maxAge)
        syncWithICloud(for: accountId)
    }

    /// Loads `accountId`'s history from its iCloud file into memory. If
    /// the file is missing or unreadable, the bucket is set to an empty
    /// array (previous in-memory state for that account is discarded).
    func load(for accountId: String) {
        let cloudSnapshots = Self.readSnapshots(for: accountId) ?? []
        histories[accountId] = Self.mergeAndPrune(cloudSnapshots, with: [], maxAge: Self.maxAge)
    }

    /// Loads histories for each `accountId` in order. Convenience wrapper
    /// for coordinators that seed the store right after `AccountRegistry`
    /// produces its known account list.
    func loadAll(accountIds: [String]) {
        for accountId in accountIds {
            load(for: accountId)
        }
    }

    /// Drops the in-memory bucket for `accountId`. Does NOT delete the
    /// iCloud file; account removal (which deletes the whole per-account
    /// iCloud directory) is handled by `AccountRegistry` per task 2.5.
    func forget(accountId: String) {
        histories.removeValue(forKey: accountId)
    }

    // MARK: - iCloud Sync (per account)

    private func syncWithICloud(for accountId: String) {
        let localSnapshots = histories[accountId] ?? []
        let cloudSnapshots = Self.readSnapshots(for: accountId) ?? []
        let merged = Self.mergeAndPrune(localSnapshots, with: cloudSnapshots, maxAge: Self.maxAge)
        histories[accountId] = merged
        Self.writeSnapshots(merged, for: accountId)
    }

    // MARK: - Merge / Dedupe

    private static func mergeAndPrune(
        _ primary: [UsageSnapshot],
        with secondary: [UsageSnapshot],
        maxAge: TimeInterval
    ) -> [UsageSnapshot] {
        var mergedByIdentity: [String: UsageSnapshot] = [:]
        for snapshot in primary + secondary {
            mergedByIdentity[snapshotIdentity(snapshot)] = snapshot
        }
        let cutoff = Date().addingTimeInterval(-maxAge)
        return mergedByIdentity.values
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    private static func snapshotIdentity(_ snapshot: UsageSnapshot) -> String {
        let timestamp = Int(snapshot.date.timeIntervalSince1970)
        let utilization5h = Int((snapshot.utilization5h * 10_000).rounded())
        let utilization7d = Int((snapshot.utilization7d * 10_000).rounded())
        let extraUsage5hFlag = snapshot.isUsingExtraUsage5h ? 1 : 0
        let extraUsage7dFlag = snapshot.isUsingExtraUsage7d ? 1 : 0
        return "\(timestamp)|\(utilization5h)|\(utilization7d)|\(extraUsage5hFlag)|\(extraUsage7dFlag)"
    }

    // MARK: - iCloud I/O helpers

    private static func readSnapshots(for accountId: String) -> [UsageSnapshot]? {
        guard let url = TempoICloud.usageHistoryFileURL(for: accountId),
              let data = try? Data(contentsOf: url)
        else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([UsageSnapshot].self, from: data)
    }

    private static func writeSnapshots(_ snapshots: [UsageSnapshot], for accountId: String) {
        guard let url = TempoICloud.usageHistoryFileURL(for: accountId),
              let accountDir = TempoICloud.accountDirectoryURL(for: accountId)
        else {
            // iCloud ubiquity container is unavailable. The
            // `AccountPollingWorker` already raised a critical
            // diagnostic when its own write hit the same condition, so
            // we don't escalate again here.
            return
        }

        if !FileManager.default.fileExists(atPath: accountDir.path) {
            do {
                try FileManager.default.createDirectory(
                    at: accountDir,
                    withIntermediateDirectories: true
                )
            } catch {
                Task { @MainActor in
                    DiagnosticsCenter.shared.warning(
                        kind: "icloud.write.usage-history",
                        message: "Couldn't create iCloud folder for usage history",
                        error: error
                    )
                }
                return
            }
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(snapshots)
            try data.write(to: url, options: .atomic)
        } catch {
            Task { @MainActor in
                DiagnosticsCenter.shared.warning(
                    kind: "icloud.write.usage-history",
                    message: "Couldn't save usage history to iCloud",
                    error: error
                )
            }
        }
    }
}
