import Foundation
import Observation
import WatchConnectivity

// MARK: - RefreshControlState

enum RefreshControlState: Equatable {
    case idle
    case inProgress
    case error(reason: String)

    var isInProgress: Bool {
        if case .inProgress = self { return true }
        return false
    }

    var errorReason: String? {
        if case .error(let reason) = self { return reason }
        return nil
    }
}

// MARK: - WatchRefreshCoordinator

/// Sends `RequestFreshRelay` messages to the iPhone and tracks the
/// refresh lifecycle. The coordinator observes `TokenStore.lastRelayReceivedAt`
/// to detect when a fresh relay arrives after the request was sent.
@Observable
@MainActor
final class WatchRefreshCoordinator {
    private(set) var state: RefreshControlState = .idle

    private let store: TokenStore
    private var requestSentAt: Date?
    private var timeoutTask: Task<Void, Never>?

    init(store: TokenStore) {
        self.store = store
    }

    /// Called on scene activation and on user tap. Sends
    /// `RequestFreshRelay` to the iPhone if reachable.
    func requestRefresh() {
        guard !state.isInProgress else {
            DevLog.trace(
                "AlertTrace",
                "WatchRefreshCoordinator.requestRefresh ignored: already in progress"
            )
            return
        }

        guard store.activeAccountId != nil, !store.hasNoActiveAccount else {
            DevLog.trace(
                "AlertTrace",
                "WatchRefreshCoordinator.requestRefresh skipped: no active account"
            )
            return
        }

        state = .inProgress
        requestSentAt = Date()
        reachabilityRetryTask?.cancel()

        if WCSession.default.isReachable {
            sendRefreshMessage()
        } else {
            // WCSession.isReachable is often false for a brief moment when
            // the app returns to foreground. Retry a few times before failing.
            waitForReachabilityThenSend()
        }
    }

    /// Maximum number of reachability poll attempts before giving up.
    private static let reachabilityMaxAttempts = 5
    /// Interval between reachability poll attempts (seconds).
    private static let reachabilityPollInterval: TimeInterval = 0.5

    private var reachabilityRetryTask: Task<Void, Never>?

    private func waitForReachabilityThenSend() {
        reachabilityRetryTask = Task { @MainActor [weak self] in
            for attempt in 1...Self.reachabilityMaxAttempts {
                try? await Task.sleep(for: .milliseconds(Int(Self.reachabilityPollInterval * 1000)))
                guard !Task.isCancelled else { return }
                guard let self, self.state.isInProgress else { return }

                if WCSession.default.isReachable {
                    DevLog.trace(
                        "AlertTrace",
                        "WatchRefreshCoordinator reachable after \(attempt) attempt(s)"
                    )
                    self.sendRefreshMessage()
                    return
                }
            }

            // Exhausted retries
            guard let self, self.state.isInProgress else { return }
            self.resolveWithError("iPhone not reachable")
            DevLog.trace(
                "AlertTrace",
                "WatchRefreshCoordinator.requestRefresh error: iPhone not reachable after retries"
            )
        }
    }

    private func sendRefreshMessage() {
        DevLog.trace(
            "AlertTrace",
            "WatchRefreshCoordinator.requestRefresh sending RequestFreshRelay"
        )

        WCSession.default.sendMessage(
            ["type": "RequestFreshRelay"],
            replyHandler: { [weak self] reply in
                Task { @MainActor in
                    guard let self else { return }
                    let ok = reply["ok"] as? Bool ?? false
                    if ok {
                        // iPhone acknowledged the request. Resolve immediately
                        // rather than waiting for lastRelayReceivedAt to change,
                        // because the iPhone may relay the same data (no change
                        // in timestamp) if nothing has updated since the last relay.
                        self.resolveWithSuccess()
                    } else {
                        let reason = reply["reason"] as? String ?? "Unknown error"
                        self.resolveWithError("iPhone rejected: \(reason)")
                    }
                }
            },
            errorHandler: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    let reason: String
                    if (error as NSError).domain == "WCErrorDomain" {
                        reason = "iPhone not reachable"
                    } else {
                        reason = error.localizedDescription
                    }
                    self.resolveWithError(reason)
                }
            }
        )

        startTimeout()
    }

    /// Called by the scene or an external observer when
    /// `TokenStore.lastRelayReceivedAt` changes. If we're in progress
    /// and the new timestamp is after our request, we're done.
    func checkForFreshRelay() {
        guard state.isInProgress else { return }
        guard let sentAt = requestSentAt else { return }
        guard let receivedAt = store.lastRelayReceivedAt,
              receivedAt > sentAt else { return }

        DevLog.trace(
            "AlertTrace",
            "WatchRefreshCoordinator detected fresh relay receivedAt=\(receivedAt) sentAt=\(sentAt)"
        )
        resolveWithSuccess()
    }

    private func resolveWithSuccess() {
        timeoutTask?.cancel()
        timeoutTask = nil
        reachabilityRetryTask?.cancel()
        reachabilityRetryTask = nil
        requestSentAt = nil
        state = .idle
    }

    private func resolveWithError(_ reason: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
        reachabilityRetryTask?.cancel()
        reachabilityRetryTask = nil
        requestSentAt = nil
        state = .error(reason: reason)
        DevLog.trace(
            "AlertTrace",
            "WatchRefreshCoordinator resolved with error: \(reason)"
        )
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            guard let self, self.state.isInProgress else { return }
            self.resolveWithError("No response from iPhone")
        }
    }
}
