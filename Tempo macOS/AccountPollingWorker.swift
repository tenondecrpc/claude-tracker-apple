import Foundation

// MARK: - AccountPollingWorker
//
// One polling worker per Anthropic account. Each worker owns its own
// scheduling state, rate-limit backoff, reset-timestamp reconciliation,
// and `latestUsage` snapshot. Multiple workers run concurrently and never
// share mutable state; the orchestrator (`UsagePoller`) reconciles the
// set of workers with `AccountRegistry`.
//
// Per-worker responsibilities:
// - Poll `https://api.anthropic.com/api/oauth/usage` on the account's own
//   15-minute schedule (1800s until first success, then 900s).
// - Honor `Retry-After` rate-limit backoff scoped to this worker only; the
//   retry timestamp is persisted under a per-accountId `UserDefaults` key so
//   app relaunches don't reset it.
// - Map the raw response into a `UsageState` tagged with this worker's
//   `accountId`.
// - Write the `UsageState` to the per-account iCloud path
//   (`TempoICloud.usageFileURL(for:)`). The legacy flat `Tempo/usage.json`
//   path is never touched.
// - Surface transient UI feedback through `refreshFeedback`, which the
//   orchestrator proxies to existing UI bindings.
@Observable
@MainActor
final class AccountPollingWorker {
    struct RefreshFeedback: Identifiable, Equatable {
        enum Kind: Equatable {
            case success
            case failure
        }

        let id = UUID()
        let kind: Kind
        let message: String
    }

    // MARK: Identity & collaborators

    /// Canonical `accountId` this worker polls for. Immutable after init.
    let accountId: String

    private let client: MacOSAPIClient

    // MARK: Observable state

    var lastPollAt: Date?
    var latestUsage: UsageState?
    var lastPollError: String?
    var isPolling = false
    var refreshFeedback: RefreshFeedback?
    var rateLimitRetryAt: Date? {
        didSet {
            persistRateLimitRetryAt()
        }
    }

    /// Invoked on every successful poll with this worker's `UsageState`.
    /// The orchestrator forwards this to its own `onUsageState` closure.
    var onUsageState: ((UsageState) -> Void)?

    // MARK: Private scheduling state

    private var timer: Timer?
    private var isRunning = false
    private var currentInterval: TimeInterval = 1800  // 30 minutes until first success
    private var refreshFeedbackDismissTask: Task<Void, Never>?

    // MARK: Reset-timestamp reconciliation state (copied verbatim from the
    // single-account poller; must remain per-worker because utilization is
    // per-account).

    private var lastResetAt5h: Date?
    private var lastResetAt7d: Date?
    private var lastUtilization5h: Double = 0

    // MARK: Init

    init(accountId: String, client: MacOSAPIClient) {
        self.accountId = accountId
        self.client = client
        self.rateLimitRetryAt = Self.loadPersistedRateLimitRetryAt(for: accountId)
    }

    // MARK: - Start / Stop

    func start() {
        stop()
        isRunning = true
        refreshFeedback = nil

        if scheduleActiveRateLimitIfNeeded() {
            return
        }

        currentInterval = 1800
        lastPollError = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.immediatePoll()
            guard self.isRunning else { return }
            self.scheduleTimer(interval: self.currentInterval)
        }
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func resetAuthenticationBackoff(clearUsage: Bool = false) {
        timer?.invalidate()
        timer = nil
        currentInterval = 1800
        rateLimitRetryAt = nil
        lastPollError = nil
        refreshFeedback = nil
        refreshFeedbackDismissTask?.cancel()
        refreshFeedbackDismissTask = nil
        if clearUsage {
            latestUsage = nil
            lastPollAt = nil
        }
    }

    func pollNow() {
        guard !isPolling else { return }
        if scheduleActiveRateLimitIfNeeded(isManualRefresh: true) {
            return
        }
        Task { [weak self] in await self?.doPoll(isManualRefresh: true) }
    }

    // MARK: - Scheduling

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.timer = nil
                guard !self.isPolling else {
                    self.scheduleTimer(interval: self.currentInterval)
                    return
                }
                await self.doPoll()
                guard self.isRunning else { return }
                self.scheduleTimer(interval: self.currentInterval)
            }
        }
    }

    private func immediatePoll() async {
        await doPoll()
    }

    // MARK: - Core Poll

    private func doPoll(isManualRefresh: Bool = false) async {
        isPolling = true
        defer { isPolling = false }
        do {
            let state = try await fetchUsage()
            currentInterval = 900
            rateLimitRetryAt = nil
            lastPollAt = Date()
            lastPollError = nil
            latestUsage = state
            try writeToiCloud(state)
            onUsageState?(state)
            if isManualRefresh {
                showRefreshFeedback(.success, message: "Updated usage just now")
            }
        } catch MacAuthError.rateLimited(let retryAfter) {
            let backoff = retryDelay(from: retryAfter)
            let retryAt = Date().addingTimeInterval(backoff)
            currentInterval = backoff
            rateLimitRetryAt = retryAt
            recordPollError(rateLimitMessage(retryAt: retryAt), isManualRefresh: isManualRefresh)
        } catch MacAuthError.httpError(let code) {
            recordPollError("API error (\(code))", isManualRefresh: isManualRefresh)
        } catch MacAuthError.noToken {
            recordPollError("Not authenticated", isManualRefresh: isManualRefresh)
        } catch {
            recordPollError(error.localizedDescription, isManualRefresh: isManualRefresh)
        }
    }

    private func retryDelay(from retryAfter: TimeInterval?) -> TimeInterval {
        let requestedDelay = retryAfter ?? currentInterval * 2
        return min(max(requestedDelay, 60), 3600)
    }

    // MARK: - Rate-limit persistence (per accountId)

    private static func rateLimitRetryAtKey(for accountId: String) -> String {
        "UsagePoller.rateLimitRetryAt.\(accountId)"
    }

    private static func loadPersistedRateLimitRetryAt(for accountId: String) -> Date? {
        let key = rateLimitRetryAtKey(for: accountId)
        let timestamp = UserDefaults.standard.double(forKey: key)
        guard timestamp > 0 else { return nil }
        let retryAt = Date(timeIntervalSince1970: timestamp)
        return retryAt > Date() ? retryAt : nil
    }

    private func persistRateLimitRetryAt() {
        let key = Self.rateLimitRetryAtKey(for: accountId)
        guard let rateLimitRetryAt else {
            UserDefaults.standard.removeObject(forKey: key)
            return
        }
        UserDefaults.standard.set(rateLimitRetryAt.timeIntervalSince1970, forKey: key)
    }

    @discardableResult
    private func scheduleActiveRateLimitIfNeeded(isManualRefresh: Bool = false) -> Bool {
        guard let retryAt = rateLimitRetryAt else { return false }
        let remaining = retryAt.timeIntervalSinceNow
        guard remaining > 0 else {
            rateLimitRetryAt = nil
            return false
        }

        currentInterval = remaining
        let message = rateLimitMessage(retryAt: retryAt)
        lastPollError = message
        scheduleTimer(interval: remaining)

        if isManualRefresh {
            showRefreshFeedback(.failure, message: "Usage is rate limited - retry in \(retryDelayLabel(until: retryAt))")
        }
        return true
    }

    var rateLimitRetryLabel: String? {
        guard let retryAt = rateLimitRetryAt, retryAt > Date() else { return nil }
        return retryDelayLabel(until: retryAt)
    }

    var isRateLimited: Bool {
        guard let retryAt = rateLimitRetryAt else { return false }
        return retryAt > Date()
    }

    private func rateLimitMessage(retryAt: Date) -> String {
        "Usage temporarily rate limited - retrying in \(retryDelayLabel(until: retryAt))"
    }

    private func retryDelayLabel(until retryAt: Date) -> String {
        Self.retryDelayLabel(seconds: retryAt.timeIntervalSinceNow)
    }

    private static func retryDelayLabel(seconds: TimeInterval) -> String {
        let minutes = max(1, Int(ceil(seconds / 60)))
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if remainingMinutes == 0 {
            return "\(hours) hr"
        }
        return "\(hours) hr \(remainingMinutes) min"
    }

    private func recordPollError(_ message: String, isManualRefresh: Bool) {
        lastPollError = message
        DevLog.trace(
            "AuthTrace",
            "Usage poll failed accountId=\(accountId) manual=\(isManualRefresh) message=\(message)"
        )
        if isManualRefresh {
            showRefreshFeedback(.failure, message: "Refresh failed - \(message)")
        }
    }

    private func showRefreshFeedback(_ kind: RefreshFeedback.Kind, message: String) {
        refreshFeedbackDismissTask?.cancel()
        let feedback = RefreshFeedback(kind: kind, message: message)
        refreshFeedback = feedback
        refreshFeedbackDismissTask = Task { @MainActor [weak self, id = feedback.id] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled, self?.refreshFeedback?.id == id else { return }
            self?.refreshFeedback = nil
        }
    }

    // MARK: - Fetch & Map

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Fetches `/api/oauth/usage` scoped to this worker's `accountId`.
    ///
    /// Guardrails (see AGENTS.md):
    /// - The request is authenticated through
    ///   `MacOSAPIClient.authenticatedRequest(for:accountId:)`, which reads
    ///   and, on 401, refreshes ONLY this worker's own Tempo Keychain slot
    ///   via `MacOSAPIClient.refreshAccessToken(for: accountId)`.
    /// - This worker MUST NEVER cause a write to the Claude Code CLI
    ///   Keychain slot (service `"Claude Code-credentials"`). That slot is
    ///   owned by the `claude` CLI and is read-only to Tempo. The CLI
    ///   fallback path inside `authenticatedRequest(for:accountId:)` does
    ///   not refresh CLI tokens on 401 by design.
    /// - The emitted `UsageState.accountId` is always this worker's
    ///   `accountId`; the iCloud write target is the per-account path
    ///   (`TempoICloud.usageFileURL(for: accountId)`).
    private func fetchUsage() async throws -> UsageState {
        let data = try await client.authenticatedRequest(
            for: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
            accountId: accountId
        )

        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        struct RawExtraUsage: Decodable {
            let is_enabled: Bool
            let used_credits: Double?
            let monthly_limit: Double?
            let utilization: Double?
        }
        struct Response: Decodable {
            let five_hour: Window
            let seven_day: Window
            let extra_usage: RawExtraUsage?
        }

        let response = try JSONDecoder().decode(Response.self, from: data)
        let isDoubleLimitPromoActive = UsagePromoDetector.detectDoubleLimitPromo(from: data)

        // Normalize utilization from 0-100 to 0.0-1.0
        let utilization5h = (response.five_hour.utilization ?? 0) / 100.0
        let utilization7d = (response.seven_day.utilization ?? 0) / 100.0

        let rawResetAt5h = response.five_hour.resets_at.flatMap { Self.isoFormatter.date(from: $0) }
        let rawResetAt7d = response.seven_day.resets_at.flatMap { Self.isoFormatter.date(from: $0) }

        // Reset-timestamp reconciliation:
        // Preserve previous value if server omits it; discard on utilization drop (rollover).
        let didReset5h = lastUtilization5h > 0.01 && utilization5h < 0.01
        let resetAt5h: Date
        if let raw = rawResetAt5h {
            resetAt5h = raw
        } else if didReset5h {
            resetAt5h = Date().addingTimeInterval(5 * 3600)
        } else {
            resetAt5h = lastResetAt5h ?? Date().addingTimeInterval(5 * 3600)
        }

        let resetAt7d: Date
        if let raw = rawResetAt7d {
            resetAt7d = raw
        } else {
            resetAt7d = lastResetAt7d ?? Date().addingTimeInterval(7 * 24 * 3600)
        }

        lastUtilization5h = utilization5h
        lastResetAt5h = resetAt5h
        lastResetAt7d = resetAt7d

        let extraUsage = response.extra_usage.map { raw in
            ExtraUsage(
                isEnabled: raw.is_enabled,
                usedCredits: raw.used_credits,
                monthlyLimit: raw.monthly_limit,
                utilization: raw.utilization
            )
        }

        return UsageState(
            accountId: accountId,
            utilization5h: utilization5h,
            utilization7d: utilization7d,
            resetAt5h: resetAt5h,
            resetAt7d: resetAt7d,
            isMocked: false,
            extraUsage: extraUsage,
            isDoubleLimitPromoActive: isDoubleLimitPromoActive
        )
    }

    // MARK: - iCloud Write (per account)

    private func writeToiCloud(_ state: UsageState) throws {
        guard let fileURL = TempoICloud.usageFileURL(for: accountId),
              let accountDir = TempoICloud.accountDirectoryURL(for: accountId)
        else {
            // iCloud ubiquity container is unavailable. Skip the write silently
            // (matches the single-account poller's tolerance of offline state).
            return
        }

        if !FileManager.default.fileExists(atPath: accountDir.path) {
            try FileManager.default.createDirectory(
                at: accountDir,
                withIntermediateDirectories: true
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}
