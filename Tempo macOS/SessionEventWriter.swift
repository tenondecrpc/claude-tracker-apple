import Foundation

@MainActor
final class SessionEventWriter {
    private enum DefaultsKey {
        static let lastWrittenSessionID = "session-writer.lastWrittenSessionID"
    }

    private struct SessionCandidate {
        let fileURL: URL
        let projectDirName: String
        let modifiedAt: Date
    }

    nonisolated private static let projectsRootURL: URL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

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

            guard let latestSession else { return }
            guard latestSession.sessionId != lastWrittenSessionID else { return }

            try writeLatestSessionToICloud(latestSession)
            lastWrittenSessionID = latestSession.sessionId
            print("[SessionWriter] wrote latest.json for session id=\(latestSession.sessionId)")
        } catch {
            print("[SessionWriter] failed to write latest session: \(error.localizedDescription)")
        }
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
        let candidates = try latestSessionCandidates()
            .sorted(by: { $0.modifiedAt > $1.modifiedAt })

        for candidate in candidates {
            let age = now.timeIntervalSince(candidate.modifiedAt)
            guard age >= idleThreshold else { continue }
            if let info = parseSessionInfo(from: candidate) {
                return info
            }
        }
        return nil
    }

    nonisolated private static func latestSessionCandidates() throws -> [SessionCandidate] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsRootURL.path) else { return [] }
        let projectEntries = try fm.contentsOfDirectory(at: projectsRootURL, includingPropertiesForKeys: nil)

        var candidates: [SessionCandidate] = []

        for projectURL in projectEntries {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: projectURL.path, isDirectory: &isDir), isDir.boolValue else { continue }
            let projectDirName = projectURL.lastPathComponent
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

    nonisolated private static func parseSessionInfo(from candidate: SessionCandidate) -> SessionInfo? {
        let decoder = JSONDecoder()
        guard let data = try? Data(contentsOf: candidate.fileURL) else { return nil }
        let lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return nil }

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

        guard totalInputTokens > 0 || totalOutputTokens > 0 else { return nil }

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

private struct JSONLRecord: Decodable {
    let type: String
    let timestamp: String?
    let message: JSONLMessage?
}

private struct JSONLMessage: Decodable {
    let model: String?
    let usage: JSONLUsage?
}

private struct JSONLUsage: Decodable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}
