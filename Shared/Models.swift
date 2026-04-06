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

struct SessionInfo: Codable, Identifiable {
    let sessionId: String
    let inputTokens: Int
    let outputTokens: Int
    let costUSD: Double
    let durationSeconds: Int
    let timestamp: Date

    var id: String { sessionId }
}

struct UsageState: Codable {
    var utilization5h: Double
    var utilization7d: Double
    var resetAt5h: Date
    var resetAt7d: Date
    var isMocked: Bool
    var extraUsage: ExtraUsage?
    var isDoubleLimitPromoActive: Bool?

    var isUsingExtraUsage5h: Bool {
        extraUsage?.isEnabled == true && utilization5h >= 0.999
    }

    var isUsingExtraUsage7d: Bool {
        extraUsage?.isEnabled == true && utilization7d >= 0.999
    }

    var isUsingExtraUsage: Bool {
        isUsingExtraUsage5h || isUsingExtraUsage7d
    }

    static var mock: UsageState {
        UsageState(
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
            isDoubleLimitPromoActive: false
        )
    }
}
