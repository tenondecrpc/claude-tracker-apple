import Foundation

// MARK: - UsageSnapshot

struct UsageSnapshot: Codable, Identifiable {
    let id: UUID
    let date: Date
    let utilization5h: Double
    let utilization7d: Double

    init(date: Date, utilization5h: Double, utilization7d: Double) {
        self.id = UUID()
        self.date = date
        self.utilization5h = utilization5h
        self.utilization7d = utilization7d
    }
}

// MARK: - UsageHistory

@Observable
@MainActor
final class UsageHistory {

    private(set) var snapshots: [UsageSnapshot] = []

    private static let storageURL: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/claude-tracker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-history.json")
    }()

    private static let maxAge: TimeInterval = 30 * 24 * 3600  // 30 days

    init() {
        load()
    }

    // MARK: - Public

    func append(_ state: UsageState) {
        let snapshot = UsageSnapshot(
            date: Date(),
            utilization5h: state.utilization5h,
            utilization7d: state.utilization7d
        )
        snapshots.append(snapshot)
        pruneOld()
        save()
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
}
