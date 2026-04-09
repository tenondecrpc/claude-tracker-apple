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

@Observable
@MainActor
final class UsageHistory {

    private(set) var snapshots: [UsageSnapshot] = []
    private var syncHistoryViaICloud: Bool

    private static let storageURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-tracker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-history.json")
    }()

    private static let maxAge: TimeInterval = 30 * 24 * 3600  // 30 days

    init(syncHistoryViaICloud: Bool = true) {
        self.syncHistoryViaICloud = syncHistoryViaICloud
        load()
        if syncHistoryViaICloud {
            syncWithICloud()
        }
    }

    // MARK: - Public

    func append(_ state: UsageState) {
        let snapshot = UsageSnapshot(
            date: Date(),
            utilization5h: state.utilization5h,
            utilization7d: state.utilization7d,
            isUsingExtraUsage5h: state.isUsingExtraUsage5h,
            isUsingExtraUsage7d: state.isUsingExtraUsage7d
        )
        snapshots.append(snapshot)
        pruneOld()
        save()
        if syncHistoryViaICloud {
            syncWithICloud()
        }
    }

    func setSyncHistoryEnabled(_ enabled: Bool) {
        syncHistoryViaICloud = enabled
        if enabled {
            syncWithICloud()
        }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        snapshots = (try? decoder.decode([UsageSnapshot].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }
        try? data.write(to: Self.storageURL, options: .atomic)
    }

    private func pruneOld() {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        snapshots.removeAll { $0.date < cutoff }
    }

    // MARK: - iCloud Sync

    private func syncWithICloud() {
        let iCloudURL = Self.iCloudMirrorURL()
        let iCloudSnapshots = Self.readSnapshots(at: iCloudURL) ?? []
        let merged = Self.mergeSnapshots(local: snapshots, cloud: iCloudSnapshots, maxAge: Self.maxAge)
        snapshots = merged
        save()
        Self.writeSnapshots(merged, to: iCloudURL)
    }

    private static func iCloudMirrorURL() -> URL {
        if let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: ClaudeTrackerICloud.containerIdentifier
        ) {
            return containerURL.appendingPathComponent("Documents/ClaudeTracker/usage-history.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/ClaudeTracker/usage-history.json")
    }

    private static func readSnapshots(at url: URL) -> [UsageSnapshot]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([UsageSnapshot].self, from: data)
    }

    private static func writeSnapshots(_ snapshots: [UsageSnapshot], to url: URL) {
        let dir = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshots) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private static func mergeSnapshots(
        local: [UsageSnapshot],
        cloud: [UsageSnapshot],
        maxAge: TimeInterval
    ) -> [UsageSnapshot] {
        var mergedByIdentity: [String: UsageSnapshot] = [:]
        for snapshot in local + cloud {
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
}
