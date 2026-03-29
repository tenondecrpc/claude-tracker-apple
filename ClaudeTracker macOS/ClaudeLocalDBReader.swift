import Foundation

// MARK: - Models

struct LocalDailyActivity: Codable {
    let date: String
    let messageCount: Int
    let sessionCount: Int
    let toolCallCount: Int
}

struct LocalDailyModelTokens: Codable {
    let date: String
    let tokensByModel: [String: Int]
}

struct LocalModelUsageItem: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int
    let cacheCreationInputTokens: Int
}

struct LocalProjectStat: Identifiable {
    var id: String { dirName }
    let dirName: String
    let displayName: String
    let sessionCount: Int
}

// MARK: - ClaudeLocalDBReader

@Observable
@MainActor
final class ClaudeLocalDBReader {

    private(set) var isAvailable = false
    private(set) var dailyActivity: [LocalDailyActivity] = []
    private(set) var dailyModelTokens: [LocalDailyModelTokens] = []
    private(set) var modelUsage: [String: LocalModelUsageItem] = [:]
    private(set) var projectStats: [LocalProjectStat] = []
    private(set) var totalSessions: Int = 0
    private(set) var totalMessages: Int = 0
    private(set) var totalSubagents: Int = 0

    private static let statsCacheURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/stats-cache.json")

    private static let projectsURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    init() {
        Task { await load() }
    }

    func reload() {
        Task { await load() }
    }

    // MARK: - Computed: 7-day window

    var activity7d: [LocalDailyActivity] {
        let cutoff = dateString(daysAgo: 7)
        return dailyActivity.filter { $0.date >= cutoff }
    }

    var messages7d: Int { activity7d.reduce(0) { $0 + $1.messageCount } }
    var sessions7d: Int { activity7d.reduce(0) { $0 + $1.sessionCount } }
    var toolCalls7d: Int { activity7d.reduce(0) { $0 + $1.toolCallCount } }

    var modelTokens7d: [String: Int] {
        let cutoff = dateString(daysAgo: 7)
        var result: [String: Int] = [:]
        for entry in dailyModelTokens where entry.date >= cutoff {
            for (model, tokens) in entry.tokensByModel {
                result[model, default: 0] += tokens
            }
        }
        return result
    }

    // MARK: - Private

    private func load() async {
        let url = Self.statsCacheURL
        let projectsURL = Self.projectsURL

        struct Loaded {
            let activity: [LocalDailyActivity]
            let modelTokens: [LocalDailyModelTokens]
            let modelUsage: [String: LocalModelUsageItem]
            let totalSessions: Int
            let totalMessages: Int
            let totalSubagents: Int
            let projects: [LocalProjectStat]
        }

        do {
            let loaded: Loaded = try await Task.detached(priority: .userInitiated) {
                let data = try Data(contentsOf: url)
                let cache = try JSONDecoder().decode(StatsCache.self, from: data)
                let projects = Self.readProjectStats(from: projectsURL)
                let subagents = Self.countSubagents(at: projectsURL)
                return Loaded(
                    activity: cache.dailyActivity,
                    modelTokens: cache.dailyModelTokens,
                    modelUsage: cache.modelUsage,
                    totalSessions: cache.totalSessions,
                    totalMessages: cache.totalMessages,
                    totalSubagents: subagents,
                    projects: projects
                )
            }.value

            dailyActivity = loaded.activity
            dailyModelTokens = loaded.modelTokens
            modelUsage = loaded.modelUsage
            totalSessions = loaded.totalSessions
            totalMessages = loaded.totalMessages
            totalSubagents = loaded.totalSubagents
            projectStats = loaded.projects
            isAvailable = true
        } catch {
            isAvailable = false
        }
    }

    private nonisolated static func readProjectStats(from url: URL) -> [LocalProjectStat] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: url.path) else { return [] }
        return entries.compactMap { dirName -> LocalProjectStat? in
            let dirURL = url.appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let count = (try? fm.contentsOfDirectory(atPath: dirURL.path))?
                .filter { $0.hasSuffix(".jsonl") }.count ?? 0
            guard count > 0 else { return nil }
            return LocalProjectStat(
                dirName: dirName,
                displayName: displayName(for: dirName),
                sessionCount: count
            )
        }
        .sorted { $0.sessionCount > $1.sessionCount }
    }

    private nonisolated static func countSubagents(at url: URL) -> Int {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(atPath: url.path) else { return 0 }
        
        var total = 0
        for project in projects {
            let subagentsURL = url.appendingPathComponent(project).appendingPathComponent("subagents")
            if let files = try? fm.contentsOfDirectory(atPath: subagentsURL.path) {
                total += files.filter { $0.hasSuffix(".jsonl") }.count
            }
        }
        return total
    }

    // Derive a short readable name from a Claude project dir name.
    // Dir names encode the filesystem path with "/" → "-", e.g.
    // "-Users-alice-Projects-my-app" → take last 2 non-empty segments → "my-app"
    private nonisolated static func displayName(for dirName: String) -> String {
        let parts = dirName.split(separator: "-", omittingEmptySubsequences: true).map(String.init)
        return parts.suffix(2).joined(separator: "-")
    }

    private func dateString(daysAgo: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

// MARK: - Private decode model

private struct StatsCache: Decodable {
    let dailyActivity: [LocalDailyActivity]
    let dailyModelTokens: [LocalDailyModelTokens]
    let modelUsage: [String: LocalModelUsageItem]
    let totalSessions: Int
    let totalMessages: Int
}
