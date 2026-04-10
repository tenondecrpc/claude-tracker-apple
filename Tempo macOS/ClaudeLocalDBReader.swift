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
    let sessions7d: Int
    let messages7d: Int
    let toolCalls7d: Int
    let totalTokens7d: Int
    let costEquiv7d: Double

    var hasActivity7d: Bool { messages7d > 0 || toolCalls7d > 0 || totalTokens7d > 0 }
}

// MARK: - JSONL decode structs (lenient)

nonisolated private struct JNLRecord: Decodable {
    let type: String
    let timestamp: String?
    let message: JNLMessage?
}

nonisolated private struct JNLMessage: Decodable {
    let content: [JNLContentBlock]?
    let usage: JNLUsage?
    let model: String?
}

nonisolated private struct JNLUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

nonisolated private struct JNLContentBlock: Decodable {
    let type: String
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
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return entries.compactMap { dirName -> LocalProjectStat? in
            let dirURL = url.appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            let jsonlFiles = (try? fm.contentsOfDirectory(atPath: dirURL.path))?
                .filter { $0.hasSuffix(".jsonl") } ?? []
            guard !jsonlFiles.isEmpty else { return nil }
            let stats7d = parseProjectStats7d(dirURL: dirURL, cutoffDate: cutoff, jsonlFiles: jsonlFiles)
            guard stats7d.hasActivity else { return nil }
            let sessions7d = jsonlFiles.filter { file -> Bool in
                let attrs = try? fm.attributesOfItem(atPath: dirURL.appendingPathComponent(file).path)
                return (attrs?[.modificationDate] as? Date).map { $0 >= cutoff } ?? false
            }.count
            return LocalProjectStat(
                dirName: dirName,
                displayName: displayName(for: dirName),
                sessionCount: jsonlFiles.count,
                sessions7d: sessions7d,
                messages7d: stats7d.messages,
                toolCalls7d: stats7d.toolCalls,
                totalTokens7d: stats7d.totalTokens,
                costEquiv7d: stats7d.costEquiv
            )
        }
        .sorted { $0.sessions7d > $1.sessions7d }
    }

    private nonisolated static func parseProjectStats7d(
        dirURL: URL,
        cutoffDate: Date,
        jsonlFiles: [String]
    ) -> (messages: Int, toolCalls: Int, totalTokens: Int, costEquiv: Double, hasActivity: Bool) {
        let fm = FileManager.default
        let decoder = JSONDecoder()
        var messages = 0
        var toolCalls = 0
        var totalTokens = 0
        var costEquiv = 0.0

        for file in jsonlFiles {
            let fileURL = dirURL.appendingPathComponent(file)
            // Fast mtime pre-filter — skip old sessions without reading content
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            if let mtime = attrs?[.modificationDate] as? Date, mtime < cutoffDate { continue }

            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            for line in lines {
                guard let record = try? decoder.decode(JNLRecord.self, from: Data(line)) else { continue }
                switch record.type {
                case "user":
                    // Count only actual human text prompts, not tool_result messages
                    let hasText = record.message?.content?.contains { $0.type == "text" } ?? false
                    if hasText { messages += 1 }
                case "assistant":
                    let msg = record.message
                    // Count tool_use blocks
                    let tools = msg?.content?.filter { $0.type == "tool_use" }.count ?? 0
                    toolCalls += tools
                    // Sum tokens
                    if let usage = msg?.usage {
                        let tokens = usage.inputTokens + usage.outputTokens
                        totalTokens += tokens
                        // Compute cost by model
                        let model = msg?.model ?? ""
                        let inM = Double(usage.inputTokens) / 1_000_000
                        let outM = Double(usage.outputTokens) / 1_000_000
                        if model.contains("opus") {
                            costEquiv += inM * 15.0 + outM * 75.0
                        } else if model.contains("sonnet") {
                            costEquiv += inM * 3.0 + outM * 15.0
                        } else if model.contains("haiku") {
                            costEquiv += inM * 1.0 + outM * 5.0
                        }
                    }
                default:
                    break
                }
            }
        }
        let hasActivity = messages > 0 || toolCalls > 0 || totalTokens > 0
        return (messages, toolCalls, totalTokens, costEquiv, hasActivity)
    }

    private nonisolated static func countSubagents(at url: URL) -> Int {
        let fm = FileManager.default
        guard let projects = try? fm.contentsOfDirectory(atPath: url.path) else { return 0 }

        var total = 0
        for project in projects {
            let projectURL = url.appendingPathComponent(project)
            guard let sessionDirs = try? fm.contentsOfDirectory(atPath: projectURL.path) else { continue }
            for sessionDir in sessionDirs {
                let subagentsURL = projectURL.appendingPathComponent(sessionDir).appendingPathComponent("subagents")
                if let files = try? fm.contentsOfDirectory(atPath: subagentsURL.path) {
                    total += files.filter { $0.hasSuffix(".jsonl") }.count
                }
            }
        }
        return total
    }

    // Derive a short readable name from a Claude project dir name.
    // Dir names encode the filesystem path with "/" → "-", e.g.
    // "-Users-alice-Projects-my-app" → take last 2 non-empty segments → "my-app"
    private nonisolated static func displayName(for dirName: String) -> String {
        if dirName.contains("claude-mem") && dirName.contains("observer-sessions") {
            return dirName.hasPrefix("-home-node") ? "claude-mem (docker)" : "claude-mem"
        }
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

nonisolated private struct StatsCache: Decodable {
    let dailyActivity: [LocalDailyActivity]
    let dailyModelTokens: [LocalDailyModelTokens]
    let modelUsage: [String: LocalModelUsageItem]
    let totalSessions: Int
    let totalMessages: Int
}
