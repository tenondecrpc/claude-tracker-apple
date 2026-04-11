import Foundation

@MainActor
final class SessionEventWriter {
    private enum DefaultsKey {
        static let lastWrittenSessionID = "session-writer.lastWrittenSessionID"
    }

    nonisolated private struct SessionCandidate {
        let fileURL: URL
        let projectDirName: String
        let modifiedAt: Date
    }

    nonisolated private static let pollInterval: TimeInterval = 20
    nonisolated private static let idleThreshold: TimeInterval = 15

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var isPolling = false

    func start() {
        stop()
        Task { await pollAndWriteIfNeeded() }
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pollAndWriteIfNeeded()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func pollAndWriteIfNeeded() async {
        guard !isPolling else { return }
        isPolling = true
        defer { isPolling = false }

        do {
            let latestSession = try await Task.detached(priority: .utility) {
                try Self.readLatestCompletedSession()
            }.value

            guard let latestSession else {
                DevLog.trace("AlertTrace", "SessionWriter found no completed session to write")
                return
            }
            guard latestSession.sessionId != lastWrittenSessionID else {
                DevLog.trace("AlertTrace", "SessionWriter skipped duplicate session id=\(latestSession.sessionId)")
                return
            }

            try writeLatestSessionToICloud(latestSession)
            lastWrittenSessionID = latestSession.sessionId
        } catch {}
    }

    private func writeLatestSessionToICloud(_ sessionInfo: SessionInfo) throws {
        let directory = iCloudTrackerDirectory()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let outputURL = directory.appendingPathComponent("latest.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sessionInfo)
        try data.write(to: outputURL, options: .atomic)
        DevLog.trace(
            "AlertTrace",
            "SessionWriter wrote latest session path=\(outputURL.path) id=\(sessionInfo.sessionId) timestamp=\(sessionInfo.timestamp)"
        )
    }

    private func iCloudTrackerDirectory() -> URL {
        if let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: TempoICloud.containerIdentifier
        ) {
            return containerURL.appendingPathComponent("Documents/Tempo")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Tempo")
    }

    private var lastWrittenSessionID: String? {
        get { defaults.string(forKey: DefaultsKey.lastWrittenSessionID) }
        set { defaults.setValue(newValue, forKey: DefaultsKey.lastWrittenSessionID) }
    }

    nonisolated private static func readLatestCompletedSession(now: Date = Date()) throws -> SessionInfo? {
        do {
            return try ClaudeLocalDBReader.withClaudeFolderAccess { claudeURL in
                let candidates = try latestSessionCandidates(in: claudeURL)
                    .sorted(by: { $0.modifiedAt > $1.modifiedAt })

                DevLog.trace("AlertTrace", "SessionWriter discovered \(candidates.count) session candidate(s)")

                for candidate in candidates {
                    let age = now.timeIntervalSince(candidate.modifiedAt)
                    guard age >= idleThreshold else {
                        DevLog.trace(
                            "AlertTrace",
                            "SessionWriter skipping active candidate file=\(candidate.fileURL.lastPathComponent) ageSeconds=\(Int(age)) threshold=\(Int(idleThreshold))"
                        )
                        continue
                    }
                    if let info = parseSessionInfo(from: candidate) {
                        DevLog.trace(
                            "AlertTrace",
                            "SessionWriter selected session id=\(info.sessionId) source=\(candidate.fileURL.path)"
                        )
                        return info
                    }
                    DevLog.trace("AlertTrace", "SessionWriter failed to parse candidate path=\(candidate.fileURL.path)")
                }
                DevLog.trace("AlertTrace", "SessionWriter did not find a parseable completed session")
                return nil
            }
        } catch ClaudeLocalDBReader.AccessError.accessRequired {
            DevLog.trace("AlertTrace", "SessionWriter cannot access ~/.claude because the app still needs folder access grant")
            return nil
        }
    }

    nonisolated private static func latestSessionCandidates(in claudeURL: URL) throws -> [SessionCandidate] {
        let fm = FileManager.default
        let projectsURL = claudeURL.appendingPathComponent("projects")
        guard fm.fileExists(atPath: projectsURL.path) else {
            DevLog.trace("AlertTrace", "SessionWriter projects directory not found at path=\(projectsURL.path)")
            return []
        }

        let projectEntries = try fm.contentsOfDirectory(at: projectsURL, includingPropertiesForKeys: nil)
        var candidates: [SessionCandidate] = []

        for projectURL in projectEntries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let projectDirName = projectURL.lastPathComponent
            if shouldIgnoreProjectDirectory(named: projectDirName) {
                DevLog.trace("AlertTrace", "SessionWriter ignoring internal project directory name=\(projectDirName)")
                continue
            }
            let files = (try? fm.contentsOfDirectory(at: projectURL, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for fileURL in files where fileURL.pathExtension == "jsonl" {
                let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
                let modifiedAt = values?.contentModificationDate ?? Date.distantPast
                candidates.append(
                    SessionCandidate(
                        fileURL: fileURL,
                        projectDirName: projectDirName,
                        modifiedAt: modifiedAt
                    )
                )
            }
        }

        return candidates
    }

    nonisolated private static func shouldIgnoreProjectDirectory(named projectDirName: String) -> Bool {
        projectDirName.contains("claude-mem-observer-sessions")
    }

    nonisolated private static func parseSessionInfo(from candidate: SessionCandidate) -> SessionInfo? {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: candidate.fileURL) else {
            DevLog.trace("AlertTrace", "SessionWriter failed reading candidate data path=\(candidate.fileURL.path)")
            return nil
        }
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        guard !lines.isEmpty else {
            DevLog.trace("AlertTrace", "SessionWriter found empty candidate file path=\(candidate.fileURL.path)")
            return nil
        }

        var totalInputTokens = 0
        var totalOutputTokens = 0
        var costUSD = 0.0

        var firstTimestamp: Date?
        var lastTimestamp: Date?

        for line in lines {
            guard let record = try? decoder.decode(JSONLRecord.self, from: Data(line)) else { continue }

            if let timestamp = parseTimestamp(record.timestamp) {
                if firstTimestamp == nil || timestamp < firstTimestamp! {
                    firstTimestamp = timestamp
                }
                if lastTimestamp == nil || timestamp > lastTimestamp! {
                    lastTimestamp = timestamp
                }
            }

            guard record.type == "assistant", let usage = record.message?.usage else { continue }
            totalInputTokens += usage.inputTokens
            totalOutputTokens += usage.outputTokens

            let model = record.message?.model ?? ""
            let inputMillions = Double(usage.inputTokens) / 1_000_000
            let outputMillions = Double(usage.outputTokens) / 1_000_000
            if model.contains("opus") {
                costUSD += inputMillions * 15.0 + outputMillions * 75.0
            } else if model.contains("sonnet") {
                costUSD += inputMillions * 3.0 + outputMillions * 15.0
            } else if model.contains("haiku") {
                costUSD += inputMillions * 1.0 + outputMillions * 5.0
            }
        }

        guard totalInputTokens > 0 || totalOutputTokens > 0 else {
            DevLog.trace("AlertTrace", "SessionWriter candidate had no assistant token usage path=\(candidate.fileURL.path)")
            return nil
        }

        let endDate = lastTimestamp ?? candidate.modifiedAt
        let startDate = firstTimestamp ?? endDate
        let durationSeconds = max(1, Int(endDate.timeIntervalSince(startDate)))
        let sessionBaseName = candidate.fileURL.deletingPathExtension().lastPathComponent
        let sessionID = "\(candidate.projectDirName):\(sessionBaseName)"

        return SessionInfo(
            sessionId: sessionID,
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            costUSD: costUSD,
            durationSeconds: durationSeconds,
            timestamp: endDate
        )
    }

    nonisolated private static func parseTimestamp(_ raw: String?) -> Date? {
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
}

nonisolated private struct JSONLRecord: Decodable {
    let type: String
    let timestamp: String?
    let message: JSONLMessage?
}

nonisolated private struct JSONLMessage: Decodable {
    let model: String?
    let usage: JSONLUsage?
}

nonisolated private struct JSONLUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
