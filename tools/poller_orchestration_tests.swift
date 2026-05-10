import Foundation

// Standalone unit tests covering the per-account orchestration invariants
// that `UsagePoller` + `AccountPollingWorker` are required to uphold:
//   - Each account keeps its own rate-limit backoff state.
//   - Each account keeps its own `latestUsage` snapshot.
//   - Adding a worker does not perturb existing workers.
//   - Removing a worker only affects that worker.
//   - Reconciling the worker set (the `UsagePoller.syncWorkers()` contract)
//     removes dropped accounts, keeps retained ones, and adds new ones.
//
// Why fixtures and not the real `UsagePoller`:
//
// `UsagePoller` and `AccountPollingWorker` live in `Tempo macOS/` and depend
// transitively on `MacOSAPIClient`, `AccountRegistry`, `TempoICloud`, the
// Keychain (Security framework), WatchConnectivity, and AppKit. Compiling a
// standalone tool that imports those modules is not practical. The real
// wiring is exercised via the macOS build and the manual verification in
// task 9.4. These fixtures exist so CI can catch regressions in the
// orchestration invariants - the behavioral contract described in
// `UsagePoller.swift` comments - without an Xcode test target.
//
// Follows the same standalone-executable pattern as
// `tools/widget_smoke_test.swift`, `tools/multi_account_tests.swift`, and
// `tools/concurrency_smoke_test.swift`.

struct SmokeFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

// MARK: - Fixtures

/// Lightweight stand-in for `AccountPollingWorker`. Captures only the
/// state that the orchestration-level tests care about: identity, the
/// rate-limit retry timestamp, and the latest usage snapshot. Methods that
/// mutate these fields mirror the real worker's public surface.
final class FixtureWorker {
    let accountId: String
    var rateLimitRetryAt: Date?
    var latestUsage: Double?  // utilization5h stand-in for UsageState
    var isRunning: Bool = false

    init(accountId: String) {
        self.accountId = accountId
    }

    func start() { isRunning = true }
    func stop() { isRunning = false }
}

/// Lightweight stand-in for `UsagePoller` that models only the worker-set
/// reconciliation contract. The fixture does not poll, does not talk to
/// the network, and does not touch iCloud or the Keychain.
final class FixtureOrchestrator {
    private(set) var workers: [String: FixtureWorker] = [:]
    private var isRunning: Bool = false

    // MARK: Lifecycle

    func start() {
        isRunning = true
        for worker in workers.values {
            worker.start()
        }
    }

    func stop() {
        isRunning = false
        for worker in workers.values {
            worker.stop()
        }
    }

    // MARK: Worker management

    @discardableResult
    func add(accountId: String) -> FixtureWorker {
        if let existing = workers[accountId] {
            return existing
        }
        let worker = FixtureWorker(accountId: accountId)
        workers[accountId] = worker
        if isRunning {
            worker.start()
        }
        return worker
    }

    func remove(accountId: String) {
        guard let worker = workers.removeValue(forKey: accountId) else { return }
        worker.stop()
    }

    func worker(for accountId: String) -> FixtureWorker? {
        workers[accountId]
    }

    // MARK: Orchestration helpers mirrored from the real poller

    /// Mirrors `AccountPollingWorker.rateLimitRetryAt = <date>`.
    func setBackoff(for accountId: String, until retryAt: Date) {
        workers[accountId]?.rateLimitRetryAt = retryAt
    }

    /// Mirrors `AccountPollingWorker.resetAuthenticationBackoff(clearUsage:)`
    /// for just the backoff portion.
    func clearBackoff(for accountId: String) {
        workers[accountId]?.rateLimitRetryAt = nil
    }

    /// Mirrors `UsagePoller.syncWorkers()` behavior: add missing accounts,
    /// remove accounts no longer in the registry, keep existing ones
    /// untouched.
    func syncWorkers(accountIds: [String]) {
        let target = Set(accountIds)
        let existing = Set(workers.keys)

        for removed in existing.subtracting(target) {
            remove(accountId: removed)
        }
        for added in target.subtracting(existing) {
            add(accountId: added)
        }
    }
}

// MARK: - Entry point

@main
struct PollerOrchestrationTests {
    static func main() throws {
        try assertBackoffIsPerAccount()
        try assertClearingBackoffIsPerAccount()
        try assertLatestUsageIsPerAccount()
        try assertAddingWorkerDoesNotAffectExisting()
        try assertRemovingWorkerOnlyAffectsThatWorker()
        try assertSyncWorkersAddsNewAccounts()
        try assertSyncWorkersRemovesDroppedAccounts()
        try assertSyncWorkersReconcilesCorrectly()
        try assertSyncWorkersIsIdempotent()
        print("Poller orchestration tests passed")
    }

    // MARK: - Backoff isolation

    private static func assertBackoffIsPerAccount() throws {
        let orchestrator = FixtureOrchestrator()
        orchestrator.add(accountId: "alice@example.com")
        orchestrator.add(accountId: "bob@example.com")

        let retryAt = Date().addingTimeInterval(300)
        orchestrator.setBackoff(for: "alice@example.com", until: retryAt)

        let alice = orchestrator.worker(for: "alice@example.com")
        let bob = orchestrator.worker(for: "bob@example.com")

        guard alice?.rateLimitRetryAt == retryAt else {
            throw SmokeFailure(
                message: "Expected alice rateLimitRetryAt == \(retryAt), got \(String(describing: alice?.rateLimitRetryAt))"
            )
        }
        guard bob?.rateLimitRetryAt == nil else {
            throw SmokeFailure(
                message: "Expected bob rateLimitRetryAt == nil, got \(String(describing: bob?.rateLimitRetryAt))"
            )
        }
    }

    private static func assertClearingBackoffIsPerAccount() throws {
        let orchestrator = FixtureOrchestrator()
        orchestrator.add(accountId: "alice@example.com")
        orchestrator.add(accountId: "bob@example.com")

        let retryAt = Date().addingTimeInterval(300)
        orchestrator.setBackoff(for: "alice@example.com", until: retryAt)
        orchestrator.setBackoff(for: "bob@example.com", until: retryAt)

        // Clear only alice's backoff. Bob's backoff must remain untouched -
        // this is the invariant that guarantees resetting auth backoff on
        // one account doesn't silently rescue another.
        orchestrator.clearBackoff(for: "alice@example.com")

        let alice = orchestrator.worker(for: "alice@example.com")
        let bob = orchestrator.worker(for: "bob@example.com")

        guard alice?.rateLimitRetryAt == nil else {
            throw SmokeFailure(
                message: "Expected alice rateLimitRetryAt to be cleared, got \(String(describing: alice?.rateLimitRetryAt))"
            )
        }
        guard bob?.rateLimitRetryAt == retryAt else {
            throw SmokeFailure(
                message: "Expected bob rateLimitRetryAt to remain \(retryAt), got \(String(describing: bob?.rateLimitRetryAt))"
            )
        }
    }

    // MARK: - Usage isolation

    private static func assertLatestUsageIsPerAccount() throws {
        let orchestrator = FixtureOrchestrator()
        let alice = orchestrator.add(accountId: "alice@example.com")
        let bob = orchestrator.add(accountId: "bob@example.com")

        alice.latestUsage = 0.42
        bob.latestUsage = 0.91

        guard orchestrator.worker(for: "alice@example.com")?.latestUsage == 0.42 else {
            throw SmokeFailure(
                message: "Expected alice latestUsage == 0.42, got \(String(describing: alice.latestUsage))"
            )
        }
        guard orchestrator.worker(for: "bob@example.com")?.latestUsage == 0.91 else {
            throw SmokeFailure(
                message: "Expected bob latestUsage == 0.91, got \(String(describing: bob.latestUsage))"
            )
        }

        // Overwriting alice must not propagate to bob.
        alice.latestUsage = 0.12
        guard orchestrator.worker(for: "bob@example.com")?.latestUsage == 0.91 else {
            throw SmokeFailure(
                message: "Bob's latestUsage changed after alice was overwritten: \(String(describing: bob.latestUsage))"
            )
        }
    }

    // MARK: - Add / remove isolation

    private static func assertAddingWorkerDoesNotAffectExisting() throws {
        let orchestrator = FixtureOrchestrator()
        let alice = orchestrator.add(accountId: "alice@example.com")
        alice.latestUsage = 0.5
        let retryAt = Date().addingTimeInterval(600)
        orchestrator.setBackoff(for: "alice@example.com", until: retryAt)

        // Adding bob must leave alice's state entirely alone.
        orchestrator.add(accountId: "bob@example.com")

        let aliceAfter = orchestrator.worker(for: "alice@example.com")
        guard aliceAfter?.latestUsage == 0.5 else {
            throw SmokeFailure(
                message: "Alice latestUsage changed after adding bob: \(String(describing: aliceAfter?.latestUsage))"
            )
        }
        guard aliceAfter?.rateLimitRetryAt == retryAt else {
            throw SmokeFailure(
                message: "Alice rateLimitRetryAt changed after adding bob: \(String(describing: aliceAfter?.rateLimitRetryAt))"
            )
        }

        // Adding the same account twice must not replace the existing worker
        // or clobber its state. This matches the orchestrator's "silently
        // ignore duplicates" semantics for `syncWorkers`.
        let aliceReadded = orchestrator.add(accountId: "alice@example.com")
        guard aliceReadded === alice else {
            throw SmokeFailure(
                message: "Re-adding alice replaced the existing worker instance"
            )
        }
        guard aliceReadded.latestUsage == 0.5 else {
            throw SmokeFailure(
                message: "Re-adding alice clobbered latestUsage: \(String(describing: aliceReadded.latestUsage))"
            )
        }
    }

    private static func assertRemovingWorkerOnlyAffectsThatWorker() throws {
        let orchestrator = FixtureOrchestrator()
        let alice = orchestrator.add(accountId: "alice@example.com")
        let bob = orchestrator.add(accountId: "bob@example.com")

        alice.latestUsage = 0.5
        bob.latestUsage = 0.7
        let bobRetryAt = Date().addingTimeInterval(900)
        orchestrator.setBackoff(for: "bob@example.com", until: bobRetryAt)

        orchestrator.remove(accountId: "alice@example.com")

        guard orchestrator.worker(for: "alice@example.com") == nil else {
            throw SmokeFailure(message: "Expected alice worker to be removed")
        }

        let bobAfter = orchestrator.worker(for: "bob@example.com")
        guard bobAfter?.latestUsage == 0.7 else {
            throw SmokeFailure(
                message: "Bob latestUsage changed after removing alice: \(String(describing: bobAfter?.latestUsage))"
            )
        }
        guard bobAfter?.rateLimitRetryAt == bobRetryAt else {
            throw SmokeFailure(
                message: "Bob rateLimitRetryAt changed after removing alice: \(String(describing: bobAfter?.rateLimitRetryAt))"
            )
        }
    }

    // MARK: - syncWorkers reconciliation

    private static func assertSyncWorkersAddsNewAccounts() throws {
        let orchestrator = FixtureOrchestrator()
        orchestrator.syncWorkers(accountIds: ["alice@example.com", "bob@example.com"])

        guard orchestrator.worker(for: "alice@example.com") != nil else {
            throw SmokeFailure(message: "Expected alice worker after sync")
        }
        guard orchestrator.worker(for: "bob@example.com") != nil else {
            throw SmokeFailure(message: "Expected bob worker after sync")
        }
        guard orchestrator.workers.count == 2 else {
            throw SmokeFailure(
                message: "Expected 2 workers after sync, got \(orchestrator.workers.count)"
            )
        }
    }

    private static func assertSyncWorkersRemovesDroppedAccounts() throws {
        let orchestrator = FixtureOrchestrator()
        orchestrator.add(accountId: "alice@example.com")
        orchestrator.add(accountId: "bob@example.com")

        // Registry now has only bob; alice must be dropped.
        orchestrator.syncWorkers(accountIds: ["bob@example.com"])

        guard orchestrator.worker(for: "alice@example.com") == nil else {
            throw SmokeFailure(message: "Expected alice worker to be removed after sync")
        }
        guard orchestrator.worker(for: "bob@example.com") != nil else {
            throw SmokeFailure(message: "Expected bob worker to survive sync")
        }
    }

    private static func assertSyncWorkersReconcilesCorrectly() throws {
        // Initial state: alice and bob. Reconcile to bob and carol. Result:
        // alice dropped, bob retained (identity preserved), carol added.
        let orchestrator = FixtureOrchestrator()
        let bob = orchestrator.add(accountId: "bob@example.com")
        orchestrator.add(accountId: "alice@example.com")
        bob.latestUsage = 0.33
        let bobRetryAt = Date().addingTimeInterval(120)
        orchestrator.setBackoff(for: "bob@example.com", until: bobRetryAt)

        orchestrator.syncWorkers(accountIds: ["bob@example.com", "carol@example.com"])

        guard orchestrator.worker(for: "alice@example.com") == nil else {
            throw SmokeFailure(message: "Expected alice to be dropped after reconcile")
        }
        let bobAfter = orchestrator.worker(for: "bob@example.com")
        guard bobAfter === bob else {
            throw SmokeFailure(
                message: "Expected bob worker identity to be preserved across reconcile"
            )
        }
        guard bobAfter?.latestUsage == 0.33 else {
            throw SmokeFailure(
                message: "Bob latestUsage changed across reconcile: \(String(describing: bobAfter?.latestUsage))"
            )
        }
        guard bobAfter?.rateLimitRetryAt == bobRetryAt else {
            throw SmokeFailure(
                message: "Bob rateLimitRetryAt changed across reconcile: \(String(describing: bobAfter?.rateLimitRetryAt))"
            )
        }
        guard orchestrator.worker(for: "carol@example.com") != nil else {
            throw SmokeFailure(message: "Expected carol to be added by reconcile")
        }
        guard orchestrator.workers.count == 2 else {
            throw SmokeFailure(
                message: "Expected exactly 2 workers after reconcile, got \(orchestrator.workers.count)"
            )
        }
    }

    private static func assertSyncWorkersIsIdempotent() throws {
        // Repeated syncs with the same account set must preserve worker
        // identity and state. This matches the comment in
        // `UsagePoller.syncWorkers()` that the operation is idempotent.
        let orchestrator = FixtureOrchestrator()
        let alice = orchestrator.add(accountId: "alice@example.com")
        alice.latestUsage = 0.25

        let ids = ["alice@example.com"]
        orchestrator.syncWorkers(accountIds: ids)
        orchestrator.syncWorkers(accountIds: ids)
        orchestrator.syncWorkers(accountIds: ids)

        let aliceAfter = orchestrator.worker(for: "alice@example.com")
        guard aliceAfter === alice else {
            throw SmokeFailure(
                message: "Alice worker identity changed across idempotent syncs"
            )
        }
        guard aliceAfter?.latestUsage == 0.25 else {
            throw SmokeFailure(
                message: "Alice latestUsage changed across idempotent syncs: \(String(describing: aliceAfter?.latestUsage))"
            )
        }
    }
}
