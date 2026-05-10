import Foundation

struct SmokeFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

@main
struct WidgetSmokeTest {
    static func main() throws {
        try assertRoutes()
        try assertAccountRouteParsing()
        try assertSnapshotRoundTrip()
        try assertMultiAccountSnapshots()
        try assertAccountIntentPlaceholder()
        try assertBuiltMacWidgetBundle()
        print("Widget smoke test passed")
    }

    // MARK: - Route tests

    private static func assertRoutes() throws {
        let statsURL = TempoWidgetRoute.stats.url
        guard statsURL.absoluteString == "tempoforclaude://stats" else {
            throw SmokeFailure(message: "Unexpected stats URL: \(statsURL.absoluteString)")
        }

        guard let parsedStats = TempoWidgetRoute(url: statsURL),
              parsedStats.kind == .stats,
              parsedStats.accountId == nil else {
            throw SmokeFailure(message: "Failed to parse stats URL")
        }

        let dashboardURL = URL(string: "tempoforclaude:///dashboard")!
        guard let parsedDashboard = TempoWidgetRoute(url: dashboardURL),
              parsedDashboard.kind == .dashboard,
              parsedDashboard.accountId == nil else {
            throw SmokeFailure(message: "Failed to parse dashboard path URL")
        }
    }

    /// Validates that the account-scoped route URL round-trips through
    /// `TempoWidgetRoute(url:)` with the accountId intact, and that the
    /// legacy accountId-less URL still parses to a route whose `accountId`
    /// is `nil` (backwards-compatible default, as documented in
    /// `TempoWidgetRoute.swift`).
    private static func assertAccountRouteParsing() throws {
        let aliceRoute = TempoWidgetRoute(kind: .dashboard, accountId: "alice@example.com")
        let aliceURL = aliceRoute.url

        // The URL string itself must be a valid absolute URL with the
        // accountId encoded as a query item. Percent-encoded `@` is
        // `%40`, matching Apple's `URLQueryItem` serialization.
        let absolute = aliceURL.absoluteString
        guard !absolute.isEmpty else {
            throw SmokeFailure(message: "Empty absoluteString for account route")
        }
        guard absolute.hasPrefix("tempoforclaude://dashboard") else {
            throw SmokeFailure(message: "Unexpected scheme/host in account route URL: \(absolute)")
        }
        guard absolute.contains("accountId=alice%40example.com")
            || absolute.contains("accountId=alice@example.com") else {
            throw SmokeFailure(message: "Missing accountId query item in account route URL: \(absolute)")
        }

        guard let parsedAlice = TempoWidgetRoute(url: aliceURL) else {
            throw SmokeFailure(message: "Failed to parse account route URL")
        }
        guard parsedAlice.kind == .dashboard else {
            throw SmokeFailure(message: "Parsed account route has wrong kind: \(parsedAlice.kind)")
        }
        guard parsedAlice.accountId == "alice@example.com" else {
            throw SmokeFailure(
                message: "Parsed account route has wrong accountId: \(parsedAlice.accountId ?? "nil")"
            )
        }

        // Legacy URL without accountId still produces a valid route whose
        // accountId is nil ("follow active account").
        let legacyURL = URL(string: "tempoforclaude://dashboard")!
        guard let legacyRoute = TempoWidgetRoute(url: legacyURL) else {
            throw SmokeFailure(message: "Failed to parse legacy account-less dashboard URL")
        }
        guard legacyRoute.kind == .dashboard, legacyRoute.accountId == nil else {
            throw SmokeFailure(
                message: "Legacy account-less URL produced unexpected route: kind=\(legacyRoute.kind) accountId=\(legacyRoute.accountId ?? "nil")"
            )
        }
    }

    // MARK: - Snapshot tests

    private static func assertSnapshotRoundTrip() throws {
        let overrideDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tempo-widget-smoke-\(UUID().uuidString)", isDirectory: true)

        setenv("TEMPO_WIDGET_SNAPSHOT_OVERRIDE_DIR", overrideDirectory.path, 1)
        defer {
            unsetenv("TEMPO_WIDGET_SNAPSHOT_OVERRIDE_DIR")
            try? FileManager.default.removeItem(at: overrideDirectory)
        }

        let usage = UsageState(
            accountId: "alice@example.com",
            utilization5h: 0.42,
            utilization7d: 0.18,
            resetAt5h: Date(timeIntervalSince1970: 1_700_000_600),
            resetAt7d: Date(timeIntervalSince1970: 1_700_086_400),
            isMocked: true,
            extraUsage: ExtraUsage(
                isEnabled: true,
                usedCredits: 0,
                monthlyLimit: 2000,
                utilization: 0
            ),
            isDoubleLimitPromoActive: false
        )
        let snapshot = WidgetUsageSnapshot(
            usage: usage,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            accountLabel: "Alice"
        )
        guard TempoWidgetSnapshotStore.write(snapshot, platform: .macOS) else {
            throw SmokeFailure(message: "Snapshot write failed")
        }

        // Round-tripping a snapshot by accountId must not depend on the
        // active-account pointer, so read by accountId directly here.
        guard let restored = TempoWidgetSnapshotStore.read(
            accountId: "alice@example.com",
            platform: .macOS
        ) else {
            throw SmokeFailure(message: "Snapshot read failed")
        }

        guard restored.schemaVersion == snapshot.schemaVersion else {
            throw SmokeFailure(message: "Schema version mismatch")
        }
        guard restored.updatedAt == snapshot.updatedAt else {
            throw SmokeFailure(message: "updatedAt mismatch")
        }
        guard restored.accountId == snapshot.accountId else {
            throw SmokeFailure(message: "accountId mismatch")
        }
        guard restored.accountLabel == snapshot.accountLabel else {
            throw SmokeFailure(message: "accountLabel mismatch")
        }
        guard restored.utilization5h == snapshot.utilization5h else {
            throw SmokeFailure(message: "utilization5h mismatch")
        }
        guard restored.utilization7d == snapshot.utilization7d else {
            throw SmokeFailure(message: "utilization7d mismatch")
        }
        guard restored.resetAt5h == snapshot.resetAt5h else {
            throw SmokeFailure(message: "resetAt5h mismatch")
        }
        guard restored.resetAt7d == snapshot.resetAt7d else {
            throw SmokeFailure(message: "resetAt7d mismatch")
        }
        guard restored.isMocked == snapshot.isMocked else {
            throw SmokeFailure(message: "isMocked mismatch")
        }
        guard restored.isDoubleLimitPromoActive == snapshot.isDoubleLimitPromoActive else {
            throw SmokeFailure(message: "promo flag mismatch")
        }
        guard restored.extraUsageEnabled == snapshot.extraUsageEnabled else {
            throw SmokeFailure(message: "extra usage enabled mismatch")
        }
        guard restored.extraUsageUsedAmountUSD == snapshot.extraUsageUsedAmountUSD else {
            throw SmokeFailure(message: "extra usage used mismatch")
        }
        guard restored.extraUsageLimitAmountUSD == snapshot.extraUsageLimitAmountUSD else {
            throw SmokeFailure(message: "extra usage limit mismatch")
        }
        guard restored.extraUsageUtilizationPercent == snapshot.extraUsageUtilizationPercent else {
            throw SmokeFailure(message: "extra usage utilization mismatch")
        }
    }

    /// Exercises the per-account + active-account-pointer layout added in
    /// the multi-account-support change: snapshots for two different
    /// accounts must coexist on disk, `read(platform:)` must follow the
    /// pointer, `read(accountId:platform:)` must target a specific
    /// account, and `knownAccountIds(platform:)` must enumerate both.
    private static func assertMultiAccountSnapshots() throws {
        let overrideDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tempo-widget-smoke-multi-\(UUID().uuidString)", isDirectory: true)

        setenv("TEMPO_WIDGET_SNAPSHOT_OVERRIDE_DIR", overrideDirectory.path, 1)
        defer {
            unsetenv("TEMPO_WIDGET_SNAPSHOT_OVERRIDE_DIR")
            try? FileManager.default.removeItem(at: overrideDirectory)
        }

        let aliceId = "alice@example.com"
        let bobId = "bob@example.com"

        let aliceSnapshot = makeSnapshot(
            accountId: aliceId,
            accountLabel: "Alice",
            utilization5h: 0.42,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let bobSnapshot = makeSnapshot(
            accountId: bobId,
            accountLabel: "Bob",
            utilization5h: 0.77,
            updatedAt: Date(timeIntervalSince1970: 1_700_100_000)
        )

        guard TempoWidgetSnapshotStore.write(aliceSnapshot, platform: .macOS) else {
            throw SmokeFailure(message: "Alice snapshot write failed")
        }
        guard TempoWidgetSnapshotStore.write(bobSnapshot, platform: .macOS) else {
            throw SmokeFailure(message: "Bob snapshot write failed")
        }

        // Point at alice and confirm `read(platform:)` resolves via the
        // pointer to alice's snapshot.
        guard TempoWidgetSnapshotStore.write(activeAccountId: aliceId, platform: .macOS) else {
            throw SmokeFailure(message: "Writing active-account pointer for alice failed")
        }
        guard let activeForAlice = TempoWidgetSnapshotStore.read(platform: .macOS) else {
            throw SmokeFailure(message: "read(platform:) returned nil while pointer was alice")
        }
        guard activeForAlice.accountId == aliceId, activeForAlice.accountLabel == "Alice" else {
            throw SmokeFailure(
                message: "Pointer-resolved snapshot did not match alice (got accountId=\(activeForAlice.accountId), label=\(activeForAlice.accountLabel))"
            )
        }

        // `read(accountId:platform:)` must return bob independently of the
        // active-account pointer.
        guard let bobRestored = TempoWidgetSnapshotStore.read(accountId: bobId, platform: .macOS) else {
            throw SmokeFailure(message: "Direct read of bob snapshot returned nil")
        }
        guard bobRestored.accountId == bobId, bobRestored.accountLabel == "Bob" else {
            throw SmokeFailure(
                message: "Direct read of bob snapshot returned wrong account (got accountId=\(bobRestored.accountId), label=\(bobRestored.accountLabel))"
            )
        }

        // `knownAccountIds` must enumerate both accounts. Order is
        // filesystem-dependent, so compare as a set.
        let known = Set(TempoWidgetSnapshotStore.knownAccountIds(platform: .macOS))
        guard known.contains(aliceId), known.contains(bobId) else {
            throw SmokeFailure(
                message: "knownAccountIds missing expected ids: got \(known.sorted())"
            )
        }

        // Flip the pointer to bob and confirm `read(platform:)` follows it.
        guard TempoWidgetSnapshotStore.write(activeAccountId: bobId, platform: .macOS) else {
            throw SmokeFailure(message: "Writing active-account pointer for bob failed")
        }
        guard let activeForBob = TempoWidgetSnapshotStore.read(platform: .macOS) else {
            throw SmokeFailure(message: "read(platform:) returned nil while pointer was bob")
        }
        guard activeForBob.accountId == bobId else {
            throw SmokeFailure(
                message: "Pointer flip to bob did not change resolved snapshot (got \(activeForBob.accountId))"
            )
        }

        // Clear the pointer. The no-intent `read(platform:)` path must now
        // return nil even though per-account snapshots still exist on disk.
        guard TempoWidgetSnapshotStore.write(activeAccountId: nil, platform: .macOS) else {
            throw SmokeFailure(message: "Clearing active-account pointer failed")
        }
        if TempoWidgetSnapshotStore.read(platform: .macOS) != nil {
            throw SmokeFailure(message: "read(platform:) returned a snapshot after pointer was cleared")
        }
        if TempoWidgetSnapshotStore.readActiveAccountId(platform: .macOS) != nil {
            throw SmokeFailure(message: "readActiveAccountId still returned an id after pointer was cleared")
        }
    }

    /// The `SelectAccountIntent` / `AccountEntity` types live in the
    /// widget extension targets and rely on `AppIntents`, which is not
    /// linkable from this standalone Swift tool. We cannot render the
    /// intent's placeholder view directly; instead, assert that the
    /// route URL the widget produces when it embeds a pinned accountId
    /// in its tap deep-link is well-formed and non-empty. That URL is
    /// what the widget extension actually emits, so a failure here
    /// signals the deep-link contract has regressed.
    private static func assertAccountIntentPlaceholder() throws {
        let route = TempoWidgetRoute(kind: .dashboard, accountId: "alice@example.com")
        let absolute = route.url.absoluteString
        guard !absolute.isEmpty else {
            throw SmokeFailure(message: "AccountIntent placeholder route produced empty URL")
        }
        // Round-trip through the parser so we know the widget-side URL is
        // valid enough for the host app to consume.
        guard let parsed = TempoWidgetRoute(url: route.url),
              parsed.kind == .dashboard,
              parsed.accountId == "alice@example.com" else {
            throw SmokeFailure(message: "AccountIntent placeholder route did not round-trip: \(absolute)")
        }
    }

    // MARK: - Shared helpers

    private static func makeSnapshot(
        accountId: String,
        accountLabel: String,
        utilization5h: Double,
        updatedAt: Date
    ) -> WidgetUsageSnapshot {
        let usage = UsageState(
            accountId: accountId,
            utilization5h: utilization5h,
            utilization7d: 0.18,
            resetAt5h: Date(timeIntervalSince1970: 1_700_000_600),
            resetAt7d: Date(timeIntervalSince1970: 1_700_086_400),
            isMocked: true,
            extraUsage: ExtraUsage(
                isEnabled: true,
                usedCredits: 0,
                monthlyLimit: 2000,
                utilization: 0
            ),
            isDoubleLimitPromoActive: false
        )
        return WidgetUsageSnapshot(
            usage: usage,
            updatedAt: updatedAt,
            accountLabel: accountLabel
        )
    }

    // MARK: - Built widget bundle

    private static func assertBuiltMacWidgetBundle() throws {
        let appPath = "/tmp/tempo-macos-final/Debug/TempoForClaude.app/Contents/Info.plist"
        let widgetPath = "/tmp/tempo-macos-final/Debug/TempoForClaude.app/Contents/PlugIns/Tempo macOS Widget.appex/Contents/Info.plist"

        let appInfo = try loadPlist(at: appPath)
        let widgetInfo = try loadPlist(at: widgetPath)

        let appBundleID = try stringValue(for: "CFBundleIdentifier", in: appInfo, path: appPath)
        let widgetBundleID = try stringValue(for: "CFBundleIdentifier", in: widgetInfo, path: widgetPath)

        guard widgetBundleID.hasPrefix(appBundleID + ".") else {
            throw SmokeFailure(
                message: "Widget bundle ID \(widgetBundleID) is not prefixed by app bundle ID \(appBundleID)"
            )
        }

        guard
            let extensionInfo = widgetInfo["NSExtension"] as? [String: Any],
            let extensionPoint = extensionInfo["NSExtensionPointIdentifier"] as? String,
            extensionPoint == "com.apple.widgetkit-extension"
        else {
            throw SmokeFailure(message: "Missing or invalid NSExtensionPointIdentifier in widget Info.plist")
        }
    }

    private static func loadPlist(at path: String) throws -> [String: Any] {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = object as? [String: Any] else {
            throw SmokeFailure(message: "Expected dictionary plist at \(path)")
        }
        return dictionary
    }

    private static func stringValue(for key: String, in dictionary: [String: Any], path: String) throws -> String {
        guard let value = dictionary[key] as? String, !value.isEmpty else {
            throw SmokeFailure(message: "Missing \(key) in \(path)")
        }
        return value
    }
}
