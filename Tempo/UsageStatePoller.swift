import Foundation

@Observable
@MainActor
final class UsageStatePoller {

    var onUsageState: ((UsageState) -> Void)?

    private let client: AnthropicAPIClient
    private var timer: Timer?
    private var isRunning = false
    private var currentInterval: TimeInterval = 900  // 15 minutes

    // Reset-timestamp reconciliation state
    private var lastResetAt5h: Date?
    private var lastResetAt7d: Date?
    private var lastUtilization5h: Double = 0

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(client: AnthropicAPIClient) {
        self.client = client
    }

    // MARK: - Start / Stop (Task 4.4)

    func start() {
        stop()
        isRunning = true
        currentInterval = 900
        // Immediate poll on launch / foreground
        Task { [weak self] in await self?.immeditatePoll() }
        scheduleTimer(interval: 900)
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
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

    private func immeditatePoll() async {
        await doPoll()
        // Intentionally does not touch the timer - timer runs on its own schedule
    }

    // MARK: - Core Poll

    private func doPoll() async {
        do {
            let state = try await fetchUsage()
            currentInterval = 900  // Reset backoff on success (Task 4.5)
            onUsageState?(state)
        } catch AuthError.rateLimited(let retryAfter) {
            // Exponential backoff capped at 1 hour (Task 4.5)
            let backoff = min(max(retryAfter ?? currentInterval, currentInterval * 2), 3600)
            currentInterval = backoff
        } catch {
            // Non-fatal (network hiccup, etc.): keep current interval
        }
    }

    // MARK: - Fetch & Map (Tasks 4.2, 4.3)

    func fetchUsage() async throws -> UsageState {
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

        // Parse raw timestamps
        let rawResetAt5h = response.five_hour.resets_at.flatMap { Self.isoFormatter.date(from: $0) }
        let rawResetAt7d = response.seven_day.resets_at.flatMap { Self.isoFormatter.date(from: $0) }

        // Reset-timestamp reconciliation:
        // - Preserve previous value if server omits it
        // - Discard previous value if utilization drops (rollover detected)
        let didReset5h = lastUtilization5h > 0.01 && utilization5h < 0.01
        let resetAt5h: Date
        if let raw = rawResetAt5h {
            resetAt5h = raw
        } else if didReset5h {
            // Rollover detected but no new timestamp: use a 5h fallback
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

        // Update reconciliation state
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
}
