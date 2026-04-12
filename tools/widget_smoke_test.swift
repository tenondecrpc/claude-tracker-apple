import Foundation

struct SmokeFailure: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

@main
struct WidgetSmokeTest {
    static func main() throws {
        try assertRoutes()
        try assertSnapshotRoundTrip()
        try assertBuiltMacWidgetBundle()
        print("Widget smoke test passed")
    }

    private static func assertRoutes() throws {
        let statsURL = TempoWidgetRoute.stats.url
        guard statsURL.absoluteString == "tempoforclaude://stats" else {
            throw SmokeFailure(message: "Unexpected stats URL: \(statsURL.absoluteString)")
        }

        guard TempoWidgetRoute(url: statsURL) == .stats else {
            throw SmokeFailure(message: "Failed to parse stats URL")
        }

        let dashboardURL = URL(string: "tempoforclaude:///dashboard")!
        guard TempoWidgetRoute(url: dashboardURL) == .dashboard else {
            throw SmokeFailure(message: "Failed to parse dashboard path URL")
        }
    }

    private static func assertSnapshotRoundTrip() throws {
        let overrideDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tempo-widget-smoke-\(UUID().uuidString)", isDirectory: true)

        setenv("TEMPO_WIDGET_SNAPSHOT_OVERRIDE_DIR", overrideDirectory.path, 1)
        defer {
            unsetenv("TEMPO_WIDGET_SNAPSHOT_OVERRIDE_DIR")
            try? FileManager.default.removeItem(at: overrideDirectory)
        }

        let usage = UsageState(
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
        let snapshot = WidgetUsageSnapshot(usage: usage, updatedAt: Date(timeIntervalSince1970: 1_700_000_000))
        guard TempoWidgetSnapshotStore.write(snapshot, platform: .macOS) else {
            throw SmokeFailure(message: "Snapshot write failed")
        }

        guard let restored = TempoWidgetSnapshotStore.read(platform: .macOS) else {
            throw SmokeFailure(message: "Snapshot read failed")
        }

        guard restored.schemaVersion == snapshot.schemaVersion else {
            throw SmokeFailure(message: "Schema version mismatch")
        }
        guard restored.updatedAt == snapshot.updatedAt else {
            throw SmokeFailure(message: "updatedAt mismatch")
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
