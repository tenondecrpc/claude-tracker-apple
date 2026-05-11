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

        guard WCSession.default.isReachable else {
            state = .error(reason: "iPhone not reachable")
            DevLog.trace(
                "AlertTrace",
                "WatchRefreshCoordinator.requestRefresh error: iPhone not reachable"
            )
            return
        }

        state = .inProgress
        requestSentAt = Date()

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
                    if !ok {
                        let reason = reply["reason"] as? String ?? "Unknown error"
                        self.resolveWithError("iPhone rejected: \(reason)")
                    }
                    // If ok == true, we wait for the relay to arrive
                    // (detected via lastRelayReceivedAt observation).
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
        requestSentAt = nil
        state = .idle
    }

    private func resolveWithError(_ reason: String) {
        timeoutTask?.cancel()
        timeoutTask = nil
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
