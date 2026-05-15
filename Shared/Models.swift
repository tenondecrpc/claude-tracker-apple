import Foundation

struct ExtraUsage: Codable {
    let isEnabled: Bool
    let usedCredits: Double?
    let monthlyLimit: Double?
    let utilization: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case usedCredits = "used_credits"
        case monthlyLimit = "monthly_limit"
        case utilization
    }

    var usedCreditsAmount: Double? { usedCredits.map { $0 / 100.0 } }
    var monthlyLimitAmount: Double? { monthlyLimit.map { $0 / 100.0 } }

    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f
    }()

    static func formatUSD(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}

nonisolated struct SessionInfo: Codable, Identifiable {
    let sessionId: String
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double
    let durationSeconds: Int
    let timestamp: Date
    /// Canonical `accountId` (see `AccountIdentifier`) that this session
    /// belongs to. Unlike `UsageState`, sessions are allowed to be
    /// unassigned: payloads without `accountId` decode successfully and the
    /// field falls back to `AccountIdentifier.unassignedAccountId`. This
    /// covers CLI-only sessions whose `oauthAccount` cannot be matched to a
    /// known Anthropic account, as well as older-format payloads that
    /// predated the multi-account layout.
    let accountId: String

    var id: String { sessionId }

    enum CodingKeys: String, CodingKey {
        case sessionId
        case inputTokens
        case outputTokens
        case costUSD
        case durationSeconds
        case timestamp
        case accountId
    }

    init(
        sessionId: String,
        inputTokens: Int,
        outputTokens: Int,
        costUSD: Double,
        durationSeconds: Int,
        timestamp: Date,
        accountId: String = AccountIdentifier.unassignedAccountId
    ) {
        self.sessionId = sessionId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = costUSD
        self.durationSeconds = durationSeconds
        self.timestamp = timestamp
        self.accountId = accountId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        inputTokens = try container.decode(Int.self, forKey: .inputTokens)
        outputTokens = try container.decode(Int.self, forKey: .outputTokens)
        costUSD = try container.decode(Double.self, forKey: .costUSD)
        durationSeconds = try container.decode(Int.self, forKey: .durationSeconds)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
            ?? AccountIdentifier.unassignedAccountId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionId, forKey: .sessionId)
        try container.encode(inputTokens, forKey: .inputTokens)
        try container.encode(outputTokens, forKey: .outputTokens)
        try container.encode(costUSD, forKey: .costUSD)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(accountId, forKey: .accountId)
    }
}

extension SessionInfo {
    /// Preview/mock fixture used by SwiftUI previews and documentation.
    /// Uses an explicit `accountId` of `"preview@example.com"` so downstream
    /// per-account filtering logic can be exercised in previews.
    static var mock: SessionInfo {
        SessionInfo(
            sessionId: "preview-1",
            inputTokens: 4200,
            outputTokens: 1800,
            costUSD: 0.12,
            durationSeconds: 142,
            timestamp: Date(),
            accountId: "preview@example.com"
        )
    }
}

struct UsageState: Codable {
    /// Canonical `accountId` (see `AccountIdentifier`) that this usage state
    /// belongs to. Required on decoding: a payload without `accountId` MUST
    /// fail to decode rather than silently defaulting. No legacy single-account
    /// payloads are supported.
    var accountId: String
    var utilization5h: Double
    var utilization7d: Double
    var resetAt5h: Date
    var resetAt7d: Date
    var isMocked: Bool
    var extraUsage: ExtraUsage?
    var isDoubleLimitPromoActive: Bool?
    /// Wall-clock moment when this state was successfully polled from the
    /// Anthropic API. Set by `AccountPollingWorker` on every successful
    /// poll and persisted to iCloud `usage.json` so downstream consumers
    /// (iOS widget, watch glance, dashboard freshness labels) report the
    /// real server-fetch time instead of the local read time.
    ///
    /// Optional for backward compatibility: payloads written before this
    /// field existed decode with `polledAt == nil`, and consumers fall
    /// back to `Date()` (the legacy behavior) until the next successful
    /// poll rewrites the file with a stamped value.
    var polledAt: Date? = nil

    var isUsingExtraUsage5h: Bool {
        extraUsage?.isEnabled == true && utilization5h >= 0.999
    }

    var isUsingExtraUsage7d: Bool {
        extraUsage?.isEnabled == true && utilization7d >= 0.999
    }

    var isUsingExtraUsage: Bool {
        isUsingExtraUsage5h || isUsingExtraUsage7d
    }

    /// Effective freshness timestamp: the real `polledAt` when present,
    /// falling back to `Date()` for legacy payloads. Widget snapshots and
    /// dashboard freshness labels MUST use this value (or `polledAt`
    /// directly with their own fallback) so the "last fetch" surface only
    /// advances on successful polls.
    var freshnessTimestamp: Date { polledAt ?? Date() }

    static var mock: UsageState {
        UsageState(
            accountId: "preview@example.com",
            utilization5h: 0.42,
            utilization7d: 0.18,
            resetAt5h: Date().addingTimeInterval(2 * 3600 + 13 * 60),
            resetAt7d: Date().addingTimeInterval(4 * 24 * 3600),
            isMocked: true,
            extraUsage: ExtraUsage(
                isEnabled: true,
                usedCredits: 0,
                monthlyLimit: 2000,
                utilization: 0
            ),
            isDoubleLimitPromoActive: false,
            polledAt: nil
        )
    }
}
