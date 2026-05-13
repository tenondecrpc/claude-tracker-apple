import Foundation

// MARK: - UsagePoller (orchestrator)
//
// `UsagePoller` owns one `AccountPollingWorker` per known Anthropic account
// and reconciles the worker set with `AccountRegistry`. It exposes a small
// "current view" surface (`latestUsage`, `lastPollAt`, `refreshFeedback`,
// etc.) that proxies the currently active account's worker so existing UI
// callers keep compiling while task 4.x reworks them to be per-account.
//
// Design notes:
// - Workers are independent. One account's rate-limit backoff, refresh
//   feedback, and in-flight polls do not affect other accounts.
// - The orchestrator does NOT observe `AccountRegistry` on its own. The
//   coordinator (`MacAppCoordinator`, task 3.6) is responsible for calling
//   `syncWorkers()` whenever the registry mutates.
// - The orchestrator re-exposes each worker's `onUsageState` through a
//   single top-level closure so coordinator code written against the
//   single-account shape (history append, widget snapshot publish) keeps
//   working. Each invocation carries the worker's own `accountId` through
//   the `UsageState.accountId` field.
@Observable
@MainActor
final class UsagePoller {

    /// Type alias so UI code that binds to `UsagePoller.RefreshFeedback`
    /// (for example `RefreshFeedbackBannerView`) keeps compiling. The
    /// concrete type lives on `AccountPollingWorker`; both symbols refer
    /// to the same value.
    typealias RefreshFeedback = AccountPollingWorker.RefreshFeedback

    // MARK: Collaborators

    private let client: MacOSAPIClient
    private let registry: AccountRegistry

    // MARK: Workers

    /// Workers indexed by `accountId`. The orchestrator is the sole owner;
    /// callers access a worker through `worker(for:)`.
    private var workers: [String: AccountPollingWorker] = [:]

    /// Tracks whether the orchestrator is currently running so `syncWorkers`
    /// can decide whether to auto-start freshly-added workers.
    private var isRunning = false

    // MARK: Callbacks

    /// Invoked whenever any worker completes a successful poll. The emitted
    /// `UsageState.accountId` matches the worker that produced it, so
    /// downstream state (history, widget snapshot) can route per-account.
    var onUsageState: ((UsageState) -> Void)?

    // MARK: Init

    init(client: MacOSAPIClient, registry: AccountRegistry) {
        self.client = client
        self.registry = registry

        for account in registry.accounts {
            let worker = makeWorker(for: account.accountId)
            workers[account.accountId] = worker
        }
    }

    // MARK: Worker factory

    private func makeWorker(for accountId: String) -> AccountPollingWorker {
        let worker = AccountPollingWorker(accountId: accountId, client: client)
        worker.onUsageState = { [weak self] state in
            self?.onUsageState?(state)
        }
        return worker
    }

    // MARK: - Lifecycle

    /// Starts polling for every known account.
    func start() {
        isRunning = true
        DevLog.trace(
            "AuthTrace",
            "UsagePoller start workers=\(workers.count) activeAccountId=\(registry.activeAccountId ?? "nil")"
        )
        for worker in workers.values {
            worker.start()
        }
    }

    /// Stops polling for every known account. Workers retain their
    /// `latestUsage` and backoff state; a subsequent `start()` resumes
    /// polling.
    func stop() {
        isRunning = false
        for worker in workers.values {
            worker.stop()
        }
    }

    // MARK: - Commands

    /// Triggers an immediate poll. When `accountId` is nil (or matches the
    /// active account), the active account's worker polls; otherwise the
    /// named worker polls. Unknown accountIds are silently ignored to match
    /// the existing "best effort" semantics.
    func pollNow(accountId: String? = nil) {
        let targetId = accountId ?? registry.activeAccountId
        guard let id = targetId, let worker = workers[id] else { return }
        worker.pollNow()
    }

    /// Resets authentication backoff for a specific account. Delegates to
    /// that account's worker. When the accountId is unknown this is a
    /// no-op; the coordinator handles reconciliation via `syncWorkers()`.
    func resetAuthenticationBackoff(for accountId: String, clearUsage: Bool = false) {
        guard let worker = workers[accountId] else { return }
        worker.resetAuthenticationBackoff(clearUsage: clearUsage)
    }

    /// Returns the worker for the given accountId, if one exists.
    func worker(for accountId: String) -> AccountPollingWorker? {
        workers[accountId]
    }

    // MARK: - Registry reconciliation

    /// Reconciles the worker set with `registry.accounts`:
    /// - Creates and starts a worker for any newly-registered accountId.
    /// - Stops and removes workers whose accountIds are no longer in the
    ///   registry. Their rate-limit retry `UserDefaults` entry persists
    ///   under a key scoped to that accountId and is not cleaned up here;
    ///   the account's sign-out cleanup (task 2.5) handles the Keychain
    ///   and iCloud data, and a stale preference key is harmless.
    ///
    /// This method is idempotent: repeated calls with an unchanged registry
    /// do no work. It does NOT mutate `registry.activeAccountId`; that is
    /// the coordinator's concern.
    func syncWorkers() {
        let currentIds = Set(registry.accounts.map { $0.accountId })
        let existingIds = Set(workers.keys)

        // Remove workers whose accounts are gone.
        for removedId in existingIds.subtracting(currentIds) {
            if let worker = workers.removeValue(forKey: removedId) {
                worker.stop()
            }
        }

        // Add workers for newly-registered accounts. Start them only when
        // the orchestrator itself is running; otherwise they remain idle and
        // will be started by the next `start()` call.
        for addedId in currentIds.subtracting(existingIds) {
            let worker = makeWorker(for: addedId)
            workers[addedId] = worker
            DevLog.trace(
                "AuthTrace",
                "UsagePoller added worker accountId=\(addedId) isRunning=\(isRunning)"
            )
            if isRunning {
                worker.start()
            }
        }
    }

    // MARK: - Active-account proxies
    //
    // These mirror the former single-account public surface so existing UI
    // bindings (menu bar icon, dashboard, detail window) continue to
    // compile while task 4.x converts them to per-account. They always
    // reflect the worker for `registry.activeAccountId`.

    var activeWorker: AccountPollingWorker? {
        guard let id = registry.activeAccountId else { return nil }
        return workers[id]
    }

    var latestUsage: UsageState? {
        get { activeWorker?.latestUsage }
        set { activeWorker?.latestUsage = newValue }
    }

    var lastPollAt: Date? { activeWorker?.lastPollAt }
    var lastPollError: String? { activeWorker?.lastPollError }
    var isPolling: Bool { activeWorker?.isPolling ?? false }
    var refreshFeedback: RefreshFeedback? { activeWorker?.refreshFeedback }
    var rateLimitRetryAt: Date? { activeWorker?.rateLimitRetryAt }
    var rateLimitRetryLabel: String? { activeWorker?.rateLimitRetryLabel }
    var isRateLimited: Bool { activeWorker?.isRateLimited ?? false }
}
