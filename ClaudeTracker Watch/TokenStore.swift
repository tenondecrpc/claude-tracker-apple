import Observation
import Foundation

@Observable @MainActor
final class TokenStore {
    private(set) var sessions: [SessionInfo] = []
    var pendingCompletion: SessionInfo? = nil
    private(set) var usageState: UsageState = .mock
    private(set) var usageHistory: [UsageHistorySnapshot] = []

    var lastSession: SessionInfo? {
        sessions.max(by: { $0.timestamp < $1.timestamp })
    }

    func apply(_ state: UsageState) {
        usageState = state
    }

    func applyHistory(_ snapshots: [UsageHistorySnapshot]) {
        usageHistory = snapshots
    }
}
