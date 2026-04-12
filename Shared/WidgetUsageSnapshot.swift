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

struct WidgetUsageSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
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

    init(usage: UsageState, updatedAt: Date) {
        schemaVersion = 1
        self.updatedAt = updatedAt
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

// MARK: - TempoWidgetSnapshotStore

enum TempoWidgetSnapshotStore {
    private static let snapshotFilename = "tempo.widget.snapshot.json"
    private static let overrideDirectoryEnvironmentKey = "TEMPO_WIDGET_SNAPSHOT_OVERRIDE_DIR"

    static func read(platform: TempoWidgetPlatform) -> WidgetUsageSnapshot? {
        guard let snapshotURL = snapshotURL(for: platform) else {
            return nil
        }

        guard let data = try? Data(contentsOf: snapshotURL) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetUsageSnapshot.self, from: data)
    }

    @discardableResult
    static func write(_ snapshot: WidgetUsageSnapshot, platform: TempoWidgetPlatform) -> Bool {
        guard let snapshotURL = snapshotURL(for: platform) else {
            return false
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(snapshot) else {
            return false
        }

        do {
            let directory = snapshotURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: snapshotURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    private static func snapshotURL(for platform: TempoWidgetPlatform) -> URL? {
        if let overridePath = ProcessInfo.processInfo.environment[overrideDirectoryEnvironmentKey], !overridePath.isEmpty {
            return URL(fileURLWithPath: overridePath, isDirectory: true)
                .appendingPathComponent(snapshotFilename)
        }

        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: platform.appGroupIdentifier
        ) else {
            return nil
        }

        return containerURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent(snapshotFilename)
    }

    #if canImport(WidgetKit)
    static func reloadTimelines(for platform: TempoWidgetPlatform) {
        for kind in platform.widgetKinds {
            WidgetCenter.shared.reloadTimelines(ofKind: kind)
        }
    }
    #endif
}
