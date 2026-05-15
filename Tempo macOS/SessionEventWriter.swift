import Foundation
import CommonCrypto

@MainActor
final class SessionEventWriter {
    private enum DefaultsKey {
        static let lastWrittenSessionID = "session-writer.lastWrittenSessionID"
        /// Last `timestamp` (as iso8601 seconds since 1970) we wrote
        /// for `lastWrittenSessionID`. Used to detect new activity on
        /// an already-seen sessionId: Claude Code keeps the same JSONL
        /// (and thus the same `sessionId`) for an entire conversation,
        /// so deduping on `sessionId` alone hides every prompt after
        /// the first. Comparing against the latest assistant timestamp
        /// lets us emit one event per turn while still skipping pure
        /// no-op rescans.
        static let lastWrittenSessionTimestamp = "session-writer.lastWrittenSessionTimestamp"
    }

    nonisolated private struct SessionCandidate {
        let fileURL: URL
        let projectDirName: String
        let modifiedAt: Date
    }

    nonisolated private static let pollInterval: TimeInterval = 20
    nonisolated private static let idleThreshold: TimeInterval = 15
    /// Only scan files modified within this window. Older sessions are already
    /// processed and tracked via `lastWrittenSessionID`.
    nonisolated private static let scanWindow: TimeInterval = 5 * 60

    private let defaults = UserDefaults.standard

    /// Registry used to resolve the current CLI `oauthAccount` email to a
    /// known Tempo `accountId`. When `nil`, or when the email does not
    /// match any registered account, sessions are tagged with
    /// `AccountIdentifier.unassignedAccountId` and routed to the
    /// `Tempo/accounts/unassigned/latest.json` bucket per design.md
    /// ("Session ingestion per account").
    private let registry: AccountRegistry?

    /// Invoked on the MainActor whenever a new (non-duplicate) session has
    /// just been written to iCloud. Receives the `accountId` the session
    /// was tagged with so the coordinator can trigger an immediate usage
    /// poll for that account, which keeps the popover and macOS widget
    /// snapshot in sync with Claude Code activity without waiting for the
    /// next 15-minute scheduled poll.
    var onSessionWritten: ((String) -> Void)?

    private var timer: Timer?
    private var isPolling = false

    /// - Parameter registry: `AccountRegistry` used to tag each written
    ///   `SessionInfo` with a canonical `accountId`. Pass `nil` only in
    ///   bootstrap contexts where no registry exists yet; all written
    ///   sessions will be routed to the `unassigned` bucket.
    init(registry: AccountRegistry? = nil) {
        self.registry = registry
    }

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
            let parsedSession = try await Task.detached(priority: .utility) {
                try Self.readLatestCompletedSession()
            }.value

            guard let parsedSession else {
                DevLog.trace("AlertTrace", "SessionWriter found no completed session to write")
                return
            }

            // Tag the parsed session with the accountId that owns it. The
            // parser intentionally leaves `accountId` at the "unassigned"
            // default; the MainActor `SessionEventWriter` resolves the
            // current CLI `oauthAccount` against the `AccountRegistry`
            // before writing to iCloud so we route to the correct
            // `Tempo/accounts/<id>/latest.json` bucket (or to
            // `accounts/unassigned/latest.json` for CLI-only sessions).
            let latestSession = taggedSession(from: parsedSession)

            // Dedup on sessionId + latest timestamp. Claude Code keeps the
            // same `sessionId` across every turn of a conversation, so
            // dedup-by-sessionId alone would only fire on the first turn
            // and silently skip all the follow-ups. Comparing the latest
            // assistant timestamp catches new activity on the same id.
            let isSameSession = latestSession.sessionId == lastWrittenSessionID
            let isSameTimestamp = isSameSession
                && lastWrittenSessionTimestamp.map { abs($0.timeIntervalSince(latestSession.timestamp)) < 1.0 } ?? false
            guard !isSameTimestamp else {
                DevLog.trace(
                    "AlertTrace",
                    "SessionWriter skipped duplicate session id=\(latestSession.sessionId) timestamp=\(latestSession.timestamp)"
                )
                return
            }

            try writeLatestSessionToICloud(latestSession)
            lastWrittenSessionID = latestSession.sessionId
            lastWrittenSessionTimestamp = latestSession.timestamp
            // Notify the coordinator so it can trigger an immediate
            // usage poll for the active account. This is the bridge
            // between "Claude Code session just ended" and "macOS widget
            // shows fresh data": without it, the widget would have to
            // wait for the next 15-minute scheduled poll.
            onSessionWritten?(latestSession.accountId)
        } catch {
            DiagnosticsCenter.shared.warning(
                kind: "session.write",
                message: "Couldn't save Claude session to iCloud",
                error: error
            )
        }
    }

    /// Returns a copy of `session` whose `accountId` is set to the
    /// currently-active account in the registry, or
    /// `AccountIdentifier.unassignedAccountId` when no account is active
    /// (bootstrap or signed-out states).
    private func taggedSession(from session: SessionInfo) -> SessionInfo {
        let accountId = resolveCurrentAccountId()
        if session.accountId == accountId { return session }
        return SessionInfo(
            sessionId: session.sessionId,
            inputTokens: session.inputTokens,
            outputTokens: session.outputTokens,
            costUSD: session.costUSD,
            durationSeconds: session.durationSeconds,
            timestamp: session.timestamp,
            accountId: accountId
        )
    }

    /// Resolve the `accountId` that should tag the next written session.
    ///
    /// Sessions are tagged with whatever account is currently active in
    /// the `AccountRegistry`. Earlier versions tried to read the email
    /// from `~/.claude.json` to disambiguate CLI sessions across multiple
    /// signed-in accounts, but the file is unreadable under App Sandbox
    /// and the lookup never succeeded in production. The active account
    /// is always the user's intent for the current foreground session,
    /// so it is a strictly better tag.
    private func resolveCurrentAccountId() -> String {
        guard let registry, let activeId = registry.activeAccountId else {
            return AccountIdentifier.unassignedAccountId
        }
        return activeId
    }

    private func writeLatestSessionToICloud(_ sessionInfo: SessionInfo) throws {
        // Route to the per-account file under
        // `Tempo/accounts/<percentEncodedAccountId>/latest.json`. When the
        // session's `accountId` is `AccountIdentifier.unassignedAccountId`
        // (the literal "unassigned"), the helper routes to
        // `Tempo/accounts/unassigned/latest.json` because "unassigned" is
        // already inside `AccountIdentifier`'s allowed directory character
        // set, so percent-encoding is a no-op.
        guard let outputURL = TempoICloud.latestSessionFileURL(for: sessionInfo.accountId),
              let accountDirectory = TempoICloud.accountDirectoryURL(for: sessionInfo.accountId) else {
            // iCloud ubiquity container unavailable. Skip the write; the
            // next poll will retry.
            DevLog.trace(
                "AlertTrace",
                "SessionWriter skipping write because iCloud container is unavailable accountId=\(sessionInfo.accountId)"
            )
            return
        }

        if !FileManager.default.fileExists(atPath: accountDirectory.path) {
            try FileManager.default.createDirectory(
                at: accountDirectory,
                withIntermediateDirectories: true
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(sessionInfo)
        try data.write(to: outputURL, options: .atomic)
        DevLog.trace(
            "AlertTrace",
            "SessionWriter wrote latest session path=\(outputURL.path) accountId=\(sessionInfo.accountId) id=\(sessionInfo.sessionId) timestamp=\(sessionInfo.timestamp)"
        )
    }

    private var lastWrittenSessionID: String? {
        get { defaults.string(forKey: DefaultsKey.lastWrittenSessionID) }
        set { defaults.setValue(newValue, forKey: DefaultsKey.lastWrittenSessionID) }
    }

    private var lastWrittenSessionTimestamp: Date? {
        get {
            let stored = defaults.double(forKey: DefaultsKey.lastWrittenSessionTimestamp)
            return stored > 0 ? Date(timeIntervalSince1970: stored) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: DefaultsKey.lastWrittenSessionTimestamp)
            } else {
                defaults.removeObject(forKey: DefaultsKey.lastWrittenSessionTimestamp)
            }
        }
    }

    nonisolated private static func readLatestCompletedSession(now: Date = Date()) throws -> SessionInfo? {
        do {
            return try ClaudeLocalDBReader.withClaudeFolderAccess { claudeURL in
                let candidates = try latestSessionCandidates(in: claudeURL, now: now)
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
                    // parseSessionInfo already logs the specific rejection reason
                    // (e.g. "no assistant token usage", "empty file", "read failed")
                }
                DevLog.trace("AlertTrace", "SessionWriter did not find a parseable completed session")
                return nil
            }
        } catch ClaudeLocalDBReader.AccessError.accessRequired {
            DevLog.trace("AlertTrace", "SessionWriter cannot access ~/.claude because the app still needs folder access grant")
            return nil
        }
    }

    nonisolated private static func latestSessionCandidates(in claudeURL: URL, now: Date = Date()) throws -> [SessionCandidate] {
        let fm = FileManager.default
        let projectsURL = claudeURL.appendingPathComponent("projects")
        guard fm.fileExists(atPath: projectsURL.path) else {
            DevLog.trace("AlertTrace", "SessionWriter projects directory not found at path=\(projectsURL.path)")
            return []
        }

        let cutoffDate = now.addingTimeInterval(-scanWindow)
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
                guard modifiedAt >= cutoffDate else { continue }
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

    /// Returns a deterministic 12-character hex SHA-256 hash of the project directory name.
    nonisolated private static func hashProjectDirName(_ name: String) -> String {
        let data = Data(name.utf8)
        let hash = data.withUnsafeBytes { buffer -> String in
            var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &digest)
            return digest.map { String(format: "%02x", $0) }.joined()
        }
        return String(hash.prefix(12))
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
        let projectPrefix = candidate.projectDirName.isEmpty ? "unknown" : hashProjectDirName(candidate.projectDirName)
        let sessionID = "\(projectPrefix):\(sessionBaseName)"

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
