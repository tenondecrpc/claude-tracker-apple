import Foundation
import AppKit

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

private struct LoadedClaudeStats {
    let activity: [LocalDailyActivity]
    let modelTokens: [LocalDailyModelTokens]
    let modelUsage: [String: LocalModelUsageItem]
    let totalSessions: Int
    let totalMessages: Int
    let totalSubagents: Int
    let projects: [LocalProjectStat]
}

// MARK: - JSONL decode structs (lenient)

nonisolated private struct JNLRecord: Decodable {
    let type: String
    let timestamp: String?
    let isMeta: Bool?
    let message: JNLMessage?
}

nonisolated private struct JNLMessage: Decodable {
    let role: String?
    let content: [JNLContentBlock]?
    let contentText: String?
    let usage: JNLUsage?
    let model: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case usage
        case model
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        usage = try container.decodeIfPresent(JNLUsage.self, forKey: .usage)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        content = try? container.decode([JNLContentBlock].self, forKey: .content)
        contentText = try? container.decode(String.self, forKey: .content)
    }
}

nonisolated private struct JNLUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadInputTokens: Int?
    let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
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
    private(set) var needsAccessGrant = false
    private(set) var needsHomeAccessGrant = false
    private(set) var dailyActivity: [LocalDailyActivity] = []
    private(set) var dailyModelTokens: [LocalDailyModelTokens] = []
    private(set) var modelUsage: [String: LocalModelUsageItem] = [:]
    private(set) var projectStats: [LocalProjectStat] = []
    private(set) var totalSessions: Int = 0
    private(set) var totalMessages: Int = 0
    private(set) var totalSubagents: Int = 0

    nonisolated static let bookmarkKey = "claudeFolderBookmark"
    nonisolated static let homeBookmarkKey = "homeFolderBookmark"

    enum AccessError: Error {
        case accessRequired
        case homeAccessRequired
    }

    init() {
        Task { await load() }
        updateHomeAccessState()
    }

    func reload() {
        Task { await load() }
        updateHomeAccessState()
    }

    private func updateHomeAccessState() {
        needsHomeAccessGrant = Self.isSandboxed && !Self.hasHomeBookmark()
    }

    // MARK: - Folder Access

    func requestFolderAccess() {
        let panel = NSOpenPanel()
        panel.message = "Click \"Grant Access\" to enable Claude Code statistics"
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if let data = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            }
            needsAccessGrant = false
            Task { await self.load() }
        }
    }

    // MARK: - Bookmark Resolution

    nonisolated static func resolveBookmarkedClaudeURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale, let fresh = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
        return url
    }

    nonisolated static func withClaudeFolderAccess<T>(_ body: (URL) throws -> T) throws -> T {
        let scopedURL = resolveBookmarkedClaudeURL()
        let accessing = scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessing {
                scopedURL?.stopAccessingSecurityScopedResource()
            }
        }

        if isSandboxed && scopedURL == nil {
            throw AccessError.accessRequired
        }

        let claudeURL = scopedURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
        return try body(claudeURL)
    }

    // MARK: - Home Directory Bookmark

    nonisolated static func resolveHomeBookmarkURL() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: homeBookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        if isStale, let fresh = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            UserDefaults.standard.set(fresh, forKey: homeBookmarkKey)
        }
        return url
    }

    static func hasHomeBookmark() -> Bool {
        resolveHomeBookmarkURL() != nil
    }

    nonisolated static func withHomeDirectoryAccess<T>(_ body: (URL) throws -> T) throws -> T {
        let scopedURL = resolveHomeBookmarkURL()
        let accessing = scopedURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if accessing {
                scopedURL?.stopAccessingSecurityScopedResource()
            }
        }

        if isSandboxed && scopedURL == nil {
            throw AccessError.homeAccessRequired
        }

        let homeURL = scopedURL ?? FileManager.default.homeDirectoryForCurrentUser
        return try body(homeURL)
    }

    func requestHomeDirectoryAccess() {
        let panel = NSOpenPanel()
        panel.message = "Tempo needs access to your home directory to detect your Claude account."
        panel.prompt = "Grant Access"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser

        panel.begin { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            if let data = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(data, forKey: Self.homeBookmarkKey)
                needsHomeAccessGrant = false
            }
            Task { await self.load() }
        }
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
        do {
            let loaded: LoadedClaudeStats = try await Task.detached(priority: .userInitiated) {
                try Self.withClaudeFolderAccess { claudeURL in
                    let statsCacheURL = claudeURL.appendingPathComponent("stats-cache.json")
                    let projectsURL = claudeURL.appendingPathComponent("projects")
                    let subagents = Self.countSubagents(at: projectsURL)

                    if let data = try? Data(contentsOf: statsCacheURL),
                       let cache = try? JSONDecoder().decode(StatsCache.self, from: data) {
                        let projects = Self.readProjectStats(from: projectsURL)
                        return LoadedClaudeStats(
                            activity: cache.dailyActivity,
                            modelTokens: cache.dailyModelTokens,
                            modelUsage: cache.modelUsage,
                            totalSessions: cache.totalSessions,
                            totalMessages: cache.totalMessages,
                            totalSubagents: subagents,
                            projects: projects
                        )
                    }

                    return try Self.buildFallbackStats(from: projectsURL, totalSubagents: subagents)
                }
            }.value

            dailyActivity = loaded.activity
            dailyModelTokens = loaded.modelTokens
            modelUsage = loaded.modelUsage
            totalSessions = loaded.totalSessions
            totalMessages = loaded.totalMessages
            totalSubagents = loaded.totalSubagents
            projectStats = loaded.projects
            isAvailable = true
            needsAccessGrant = false
        } catch AccessError.accessRequired {
            clearLoadedStats()
            isAvailable = false
            needsAccessGrant = true
            DevLog.trace("AlertTrace", "ClaudeLocalDBReader needs .claude folder access grant")
        } catch {
            clearLoadedStats()
            isAvailable = false
            if Self.isPermissionError(error) {
                needsAccessGrant = true
            } else {
                needsAccessGrant = false
            }
        }
    }

    private func clearLoadedStats() {
        dailyActivity = []
        dailyModelTokens = []
        modelUsage = [:]
        projectStats = []
        totalSessions = 0
        totalMessages = 0
        totalSubagents = 0
        needsHomeAccessGrant = Self.isSandboxed && !Self.hasHomeBookmark()
    }

    private nonisolated static func buildFallbackStats(
        from projectsURL: URL,
        totalSubagents: Int
    ) throws -> LoadedClaudeStats {
        let fm = FileManager.default
        let projectEntries = try fm.contentsOfDirectory(atPath: projectsURL.path)
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        var dailyActivityByDate: [String: LocalDailyActivityAccumulator] = [:]
        var dailyTokensByDate: [String: [String: Int]] = [:]
        var modelUsage: [String: LocalModelUsageAccumulator] = [:]
        var projectStats: [LocalProjectStat] = []
        var totalSessions = 0
        var totalMessages = 0

        for dirName in projectEntries {
            let dirURL = projectsURL.appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirURL.path, isDirectory: &isDir), isDir.boolValue else { continue }

            let jsonlFiles = (try? fm.contentsOfDirectory(atPath: dirURL.path))?
                .filter { $0.hasSuffix(".jsonl") } ?? []
            guard !jsonlFiles.isEmpty else { continue }

            totalSessions += jsonlFiles.count

            let aggregate = aggregateProjectData(
                dirURL: dirURL,
                jsonlFiles: jsonlFiles,
                cutoffDate: cutoffDate,
                dailyActivityByDate: &dailyActivityByDate,
                dailyTokensByDate: &dailyTokensByDate,
                modelUsage: &modelUsage
            )
            totalMessages += aggregate.totalMessages

            if aggregate.hasActivity {
                projectStats.append(
                    LocalProjectStat(
                        dirName: dirName,
                        displayName: displayName(for: dirName),
                        sessionCount: jsonlFiles.count,
                        sessions7d: aggregate.sessions7d,
                        messages7d: aggregate.messages7d,
                        toolCalls7d: aggregate.toolCalls7d,
                        totalTokens7d: aggregate.totalTokens7d,
                        costEquiv7d: aggregate.costEquiv7d
                    )
                )
            }
        }

        let dailyActivity = dailyActivityByDate
            .map { date, activity in
                LocalDailyActivity(
                    date: date,
                    messageCount: activity.messageCount,
                    sessionCount: activity.sessionCount,
                    toolCallCount: activity.toolCallCount
                )
            }
            .sorted { $0.date < $1.date }

        let dailyModelTokens = dailyTokensByDate
            .map { date, tokensByModel in
                LocalDailyModelTokens(
                    date: date,
                    tokensByModel: tokensByModel
                )
            }
            .sorted { $0.date < $1.date }

        let finalModelUsage = modelUsage.mapValues { usage in
            LocalModelUsageItem(
                inputTokens: usage.inputTokens,
                outputTokens: usage.outputTokens,
                cacheReadInputTokens: usage.cacheReadInputTokens,
                cacheCreationInputTokens: usage.cacheCreationInputTokens
            )
        }

        guard !dailyActivity.isEmpty || !projectStats.isEmpty || !finalModelUsage.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        return LoadedClaudeStats(
            activity: dailyActivity,
            modelTokens: dailyModelTokens,
            modelUsage: finalModelUsage,
            totalSessions: totalSessions,
            totalMessages: totalMessages,
            totalSubagents: totalSubagents,
            projects: projectStats.sorted { $0.sessions7d > $1.sessions7d }
        )
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
            // Fast mtime pre-filter - skip old sessions without reading content
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            if let mtime = attrs?[.modificationDate] as? Date, mtime < cutoffDate { continue }

            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            for line in lines {
                guard let record = try? decoder.decode(JNLRecord.self, from: Data(line)) else { continue }
                switch record.type {
                case "user":
                    if isCountableUserMessage(record) {
                        messages += 1
                    }
                case "assistant":
                    let msg = record.message
                    // Count tool_use blocks
                    let tools = msg?.content?.filter { $0.type == "tool_use" }.count ?? 0
                    toolCalls += tools
                    // Sum tokens
                    if let usage = msg?.usage {
                        let tokens = usage.inputTokens + usage.outputTokens
                        totalTokens += tokens
                        costEquiv += costEquivalent(
                            model: msg?.model ?? "",
                            inputTokens: usage.inputTokens,
                            outputTokens: usage.outputTokens
                        )
                    }
                default:
                    break
                }
            }
        }
        let hasActivity = messages > 0 || toolCalls > 0 || totalTokens > 0
        return (messages, toolCalls, totalTokens, costEquiv, hasActivity)
    }

    private nonisolated static func aggregateProjectData(
        dirURL: URL,
        jsonlFiles: [String],
        cutoffDate: Date,
        dailyActivityByDate: inout [String: LocalDailyActivityAccumulator],
        dailyTokensByDate: inout [String: [String: Int]],
        modelUsage: inout [String: LocalModelUsageAccumulator]
    ) -> (
        sessions7d: Int,
        messages7d: Int,
        toolCalls7d: Int,
        totalTokens7d: Int,
        costEquiv7d: Double,
        totalMessages: Int,
        hasActivity: Bool
    ) {
        let fm = FileManager.default
        let decoder = JSONDecoder()

        var sessions7d = 0
        var messages7d = 0
        var toolCalls7d = 0
        var totalTokens7d = 0
        var costEquiv7d = 0.0
        var totalMessages = 0

        for file in jsonlFiles {
            let fileURL = dirURL.appendingPathComponent(file)
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            let modifiedAt = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            let sessionDateString = dayString(from: modifiedAt)
            let isInLast7Days = modifiedAt >= cutoffDate

            if isInLast7Days {
                sessions7d += 1
                dailyActivityByDate[sessionDateString, default: .init()].sessionCount += 1
            }

            guard let data = try? Data(contentsOf: fileURL) else { continue }
            let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            for line in lines {
                guard let record = try? decoder.decode(JNLRecord.self, from: Data(line)) else { continue }

                let eventDate = parseTimestamp(record.timestamp) ?? modifiedAt
                let eventDateString = dayString(from: eventDate)
                let usage = record.message?.usage
                let model = record.message?.model ?? ""

                switch record.type {
                case "user":
                    guard isCountableUserMessage(record) else { continue }
                    totalMessages += 1
                    if eventDate >= cutoffDate {
                        messages7d += 1
                        dailyActivityByDate[eventDateString, default: .init()].messageCount += 1
                    }

                case "assistant":
                    let tools = record.message?.content?.filter { $0.type == "tool_use" }.count ?? 0
                    if eventDate >= cutoffDate, tools > 0 {
                        toolCalls7d += tools
                        dailyActivityByDate[eventDateString, default: .init()].toolCallCount += tools
                    }

                    guard let usage else { continue }
                    let tokens = usage.inputTokens + usage.outputTokens

                    if !model.isEmpty {
                        var aggregate = modelUsage[model, default: .init()]
                        aggregate.inputTokens += usage.inputTokens
                        aggregate.outputTokens += usage.outputTokens
                        aggregate.cacheReadInputTokens += usage.cacheReadInputTokens ?? 0
                        aggregate.cacheCreationInputTokens += usage.cacheCreationInputTokens ?? 0
                        modelUsage[model] = aggregate
                    }

                    if eventDate >= cutoffDate {
                        totalTokens7d += tokens
                        costEquiv7d += costEquivalent(
                            model: model,
                            inputTokens: usage.inputTokens,
                            outputTokens: usage.outputTokens
                        )
                        if !model.isEmpty {
                            dailyTokensByDate[eventDateString, default: [:]][model, default: 0] += tokens
                        }
                    }

                default:
                    break
                }
            }
        }

        let hasActivity = sessions7d > 0 || messages7d > 0 || toolCalls7d > 0 || totalTokens7d > 0
        return (sessions7d, messages7d, toolCalls7d, totalTokens7d, costEquiv7d, totalMessages, hasActivity)
    }

    private nonisolated static func isCountableUserMessage(_ record: JNLRecord) -> Bool {
        guard record.isMeta != true else { return false }
        guard record.type == "user" else { return false }
        if let role = record.message?.role, role != "user" {
            return false
        }

        if let content = record.message?.content, content.contains(where: { $0.type == "text" || $0.type == "image" }) {
            return true
        }

        if let contentText = record.message?.contentText?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !contentText.isEmpty,
           !contentText.contains("<local-command"),
           !contentText.contains("<command-name>"),
           !contentText.contains("<command-message>"),
           !contentText.contains("<tool_result") {
            return true
        }

        return false
    }

    private nonisolated static func costEquivalent(
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) -> Double {
        let inM = Double(inputTokens) / 1_000_000
        let outM = Double(outputTokens) / 1_000_000

        if model.contains("opus") {
            return inM * 15.0 + outM * 75.0
        }
        if model.contains("sonnet") {
            return inM * 3.0 + outM * 15.0
        }
        if model.contains("haiku") {
            return inM * 1.0 + outM * 5.0
        }
        return 0
    }

    private nonisolated static func dayString(from date: Date) -> String {
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }

    private nonisolated static func parseTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }

        let withFractional = ISO8601DateFormatter()
        withFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractional.date(from: raw) {
            return date
        }

        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: raw)
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

    private nonisolated static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    private nonisolated static func isPermissionError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileReadNoPermissionError {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == EACCES {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain && nsError.code == EPERM {
            return true
        }
        return false
    }
}

// MARK: - Private decode model

nonisolated private struct LocalDailyActivityAccumulator {
    var messageCount = 0
    var sessionCount = 0
    var toolCallCount = 0
}

nonisolated private struct LocalModelUsageAccumulator {
    var inputTokens = 0
    var outputTokens = 0
    var cacheReadInputTokens = 0
    var cacheCreationInputTokens = 0
}

nonisolated private struct StatsCache: Decodable {
    let dailyActivity: [LocalDailyActivity]
    let dailyModelTokens: [LocalDailyModelTokens]
    let modelUsage: [String: LocalModelUsageItem]
    let totalSessions: Int
    let totalMessages: Int
}
