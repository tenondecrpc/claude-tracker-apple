import Foundation

// MARK: - UsagePoller

@Observable
@MainActor
final class UsagePoller {

    var lastPollAt: Date?
    var latestUsage: UsageState?
    var lastPollError: String?
    var isPolling = false

    private let client: MacOSAPIClient
    private var timer: Timer?
    private var isRunning = false
    private var currentInterval: TimeInterval = 1800  // 30 minutes

    // Reset-timestamp reconciliation state
    private var lastResetAt5h: Date?
    private var lastResetAt7d: Date?
    private var lastUtilization5h: Double = 0

    var onUsageState: ((UsageState) -> Void)?

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(client: MacOSAPIClient) {
        self.client = client
    }

    // MARK: - Start / Stop

    func start() {
        stop()
        isRunning = true
        currentInterval = 1800
        Task { [weak self] in await self?.immediatePoll() }
        scheduleTimer(interval: 1800)
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    func pollNow() {
        Task { [weak self] in await self?.doPoll() }
    }

    // MARK: - Scheduling

    private func scheduleTimer(interval: TimeInterval) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                self.timer = nil
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

    private func doPoll() async {
        isPolling = true
        defer { isPolling = false }
        do {
            let state = try await fetchUsage()
            currentInterval = 900
            lastPollAt = Date()
            lastPollError = nil
            latestUsage = state
            try writeToiCloud(state)
            onUsageState?(state)
        } catch MacAuthError.rateLimited(let retryAfter) {
            let backoff = min(max(retryAfter ?? currentInterval, currentInterval * 2), 3600)
            currentInterval = backoff
            lastPollError = "Rate limited — retrying in \(Int(backoff / 60)) min"
        } catch MacAuthError.httpError(let code) {
            lastPollError = "API error (\(code))"
        } catch MacAuthError.noToken {
            lastPollError = "Not authenticated"
        } catch {
            lastPollError = error.localizedDescription
        }
    }

    // MARK: - Fetch & Map (Tasks 3.1, 3.2, 3.3)

    private func fetchUsage() async throws -> UsageState {
        let data = try await client.authenticatedRequest(
            for: URL(string: "https://api.anthropic.com/api/oauth/usage")!
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

        // Normalize utilization from 0–100 to 0.0–1.0
        let utilization5h = (response.five_hour.utilization ?? 0) / 100.0
        let utilization7d = (response.seven_day.utilization ?? 0) / 100.0

        let rawResetAt5h = response.five_hour.resets_at.flatMap { Self.isoFormatter.date(from: $0) }
        let rawResetAt7d = response.seven_day.resets_at.flatMap { Self.isoFormatter.date(from: $0) }

        // Reset-timestamp reconciliation (Task 3.3):
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
            utilization5h: utilization5h,
            utilization7d: utilization7d,
            resetAt5h: resetAt5h,
            resetAt7d: resetAt7d,
            isMocked: false,
            extraUsage: extraUsage,
            isDoubleLimitPromoActive: isDoubleLimitPromoActive
        )
    }

    // MARK: - iCloud Write (Task 3.5)

    private func writeToiCloud(_ state: UsageState) throws {
        let dir = iCloudTrackerDirectory()

        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let fileURL = dir.appendingPathComponent("usage.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Returns the ClaudeTracker directory in the shared iCloud ubiquity container.
    /// Falls back to the generic iCloud Drive path when the container URL is unavailable.
    private func iCloudTrackerDirectory() -> URL {
        if let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: ClaudeTrackerICloud.containerIdentifier
        ) {
            return containerURL.appendingPathComponent("Documents/ClaudeTracker")
        }
        // Fallback: generic iCloud Drive path (macOS only, requires iCloud Drive to be enabled)
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/ClaudeTracker")
    }
}
