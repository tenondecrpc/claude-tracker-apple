import Foundation

struct UsageHistorySnapshot: Codable, Identifiable, Hashable {
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
        id: UUID = UUID(),
        date: Date,
        utilization5h: Double,
        utilization7d: Double,
        isUsingExtraUsage5h: Bool = false,
        isUsingExtraUsage7d: Bool = false
    ) {
        self.id = id
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

enum UsageHistoryRange: String, CaseIterable, Codable {
    case last24Hours
    case last7Days
    case last30Days

    var displayName: String {
        switch self {
        case .last24Hours: return "24H"
        case .last7Days: return "7D"
        case .last30Days: return "30D"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .last24Hours: return 24 * 3600
        case .last7Days: return 7 * 24 * 3600
        case .last30Days: return 30 * 24 * 3600
        }
    }
}

enum ICloudDataFreshness {
    case waiting
    case syncing
    case stale(since: Date)
}

enum ICloudFreshnessPolicy {
    static let staleThreshold: TimeInterval = 30 * 60

    static func status(lastReceivedAt: Date?, now: Date = Date()) -> ICloudDataFreshness {
        guard let lastReceivedAt else { return .waiting }
        return now.timeIntervalSince(lastReceivedAt) > staleThreshold
            ? .stale(since: lastReceivedAt)
            : .syncing
    }
}

enum UsageHistoryTransformer {
    static func filteredSnapshots(
        _ snapshots: [UsageHistorySnapshot],
        range: UsageHistoryRange,
        now: Date = Date()
    ) -> [UsageHistorySnapshot] {
        let cutoff = now.addingTimeInterval(-range.duration)
        return snapshots
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }

    static func boundedPercent(_ utilization: Double) -> Double {
        min(max(utilization * 100.0, 0), 100)
    }

    static func averageUtilization5h(_ snapshots: [UsageHistorySnapshot]) -> Double {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map(\.utilization5h).reduce(0, +) / Double(snapshots.count)
    }

    static func averageUtilization7d(_ snapshots: [UsageHistorySnapshot]) -> Double {
        guard !snapshots.isEmpty else { return 0 }
        return snapshots.map(\.utilization7d).reduce(0, +) / Double(snapshots.count)
    }

    static func burnRate(utilization5h: Double, resetAt5h: Date, now: Date = Date()) -> Double {
        let hoursUntilReset = max(0, resetAt5h.timeIntervalSince(now) / 3600)
        let hoursElapsed = max(0.1, 5.0 - hoursUntilReset)
        return boundedPercent(utilization5h) / hoursElapsed
    }
}
