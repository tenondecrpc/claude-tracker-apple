import Foundation
import OSLog

// MARK: - DiagnosticLevel

/// Severity classification for `DiagnosticEvent`.
///
/// - `info`: debug context only. Never surfaces in UI; goes only to OSLog.
/// - `warning`: a recoverable failure (the app kept working). Visible in
///   the diagnostics panel but does NOT show in the prominent UI label.
/// - `critical`: a failure the user should know about because some
///   functionality is broken or stale (iCloud unavailable, snapshot
///   write failed, ...). Surfaces in the prominent UI label until
///   replaced by a newer critical or cleared by the user.
enum DiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case critical
}

// MARK: - DiagnosticEvent

/// Single diagnostics report. Stable across encoding/decoding so the
/// diagnostics panel can persist or share recent events for support.
struct DiagnosticEvent: Identifiable, Equatable, Sendable, Codable {
    /// Stable per-event id used by SwiftUI list diffing. Generated at
    /// construction time so `recentEvents` can be observed by `@Observable`
    /// hosts without forcing identity recomputation.
    let id: UUID
    /// Stable identifier used for de-duplication and analytics-style
    /// grouping. Use dotted notation: "icloud.write.usage",
    /// "watchconnectivity.context", "widget.snapshot.write".
    let kind: String
    /// Short, user-facing message. One line, no trailing punctuation.
    let message: String
    /// Optional technical detail (typically `error.localizedDescription`
    /// or a stringified `Error`). Shown in the panel but not the label.
    let detail: String?
    let timestamp: Date
    let level: DiagnosticLevel

    init(
        id: UUID = UUID(),
        kind: String,
        message: String,
        detail: String? = nil,
        timestamp: Date = Date(),
        level: DiagnosticLevel
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.detail = detail
        self.timestamp = timestamp
        self.level = level
    }

    static func == (lhs: DiagnosticEvent, rhs: DiagnosticEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - DiagnosticsCenter

/// Always-on (non-DEBUG-gated) diagnostics sink shared by every target.
///
/// Three primary consumers:
///
/// 1. **Prominent UI label** binds to `lastCritical` and renders a
///    subtle banner whenever a critical event is active. The banner is
///    dismissed via `clearCritical()` (user gesture) or replaced by a
///    newer critical event of any kind.
///
/// 2. **Diagnostics panel** binds to `recentEvents` to show the last
///    `bufferLimit` events for support / troubleshooting. All levels
///    are recorded so a critical event surrounded by relevant warnings
///    keeps useful context.
///
/// 3. **Console.app** receives every report via the `OSLog` `Logger`
///    (subsystem = bundle id, category = `"Diagnostics"`). Unlike
///    `DevLog.trace`, this Logger is NOT gated by `#if DEBUG`, so
///    Release / TestFlight builds are queryable on user machines via
///    `log stream --predicate 'subsystem CONTAINS "tempo.claude"
///     AND category == "Diagnostics"'`.
///
/// De-duplication: consecutive reports with the same `kind` and `level`
/// within `dedupWindow` collapse the older entry rather than spamming
/// the buffer (e.g. a flapping iCloud write failure does not push 60
/// entries per minute). The buffer keeps the freshest occurrence so
/// "when did this start" is preserved by the entry's timestamp.
@Observable
@MainActor
final class DiagnosticsCenter {
    /// Process-wide sink. Each target imports `Shared/` and reaches for
    /// `DiagnosticsCenter.shared` rather than constructing its own.
    static let shared = DiagnosticsCenter()

    /// Most recent critical event. `nil` when no critical has been
    /// reported, or after `clearCritical()` was called by the user.
    /// UI dismisses the banner when this is `nil`.
    private(set) var lastCritical: DiagnosticEvent?

    /// Rolling buffer of the last `bufferLimit` events across all
    /// levels. Read-only externally; mutate only via `report` /
    /// `clearAll`.
    private(set) var recentEvents: [DiagnosticEvent] = []

    /// Cap on `recentEvents`. Older entries roll off the front.
    private static let bufferLimit = 20

    /// Window during which a repeat `kind` + `level` combo collapses
    /// onto the previous entry instead of producing a new one.
    private static let dedupWindow: TimeInterval = 30

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.tenondev.tempo.claude",
        category: "Diagnostics"
    )

    private init() {}

    /// Records a diagnostic event.
    ///
    /// - Parameters:
    ///   - kind: stable, dotted identifier used for de-duplication and
    ///     grouping. Examples: `"icloud.write.usage"`,
    ///     `"watchconnectivity.context"`, `"widget.snapshot.write"`.
    ///     Reuse the same string from every call site for the same
    ///     failure surface so dedup works.
    ///   - level: severity. `info` is recorded but never surfaces in
    ///     UI; `warning` shows in the panel; `critical` shows in the
    ///     prominent banner.
    ///   - message: short user-facing line. Do not include the kind.
    ///   - error: optional underlying error. Stored in `detail` as a
    ///     stringified description; never surfaces in the banner.
    func report(
        kind: String,
        level: DiagnosticLevel,
        message: String,
        error: Error? = nil
    ) {
        let detail = error.map { String(describing: $0) }
        let event = DiagnosticEvent(
            kind: kind,
            message: message,
            detail: detail,
            level: level
        )

        // Mirror to OSLog so users can capture diagnostics from a
        // shipped build via `log stream`. Three different Logger
        // levels keep the predicate filtering useful: `--info` /
        // `--debug` flags expose progressively more detail when
        // someone is debugging a user issue.
        let detailField = detail ?? "nil"
        switch level {
        case .info:
            logger.info("[\(kind, privacy: .public)] \(message, privacy: .public) detail=\(detailField, privacy: .public)")
        case .warning:
            logger.notice("[\(kind, privacy: .public)] \(message, privacy: .public) detail=\(detailField, privacy: .public)")
        case .critical:
            logger.error("[\(kind, privacy: .public)] \(message, privacy: .public) detail=\(detailField, privacy: .public)")
        }

        // De-duplicate same-kind / same-level reports within the
        // dedupe window. We discard the older entry and append the
        // newer one so the buffer always carries the freshest
        // occurrence's timestamp and message.
        if let last = recentEvents.last,
           last.kind == kind,
           last.level == level,
           event.timestamp.timeIntervalSince(last.timestamp) < Self.dedupWindow {
            recentEvents.removeLast()
        }
        recentEvents.append(event)
        if recentEvents.count > Self.bufferLimit {
            recentEvents.removeFirst(recentEvents.count - Self.bufferLimit)
        }

        if level == .critical {
            lastCritical = event
        }
    }

    /// Convenience for the most common warning shape: "this thing
    /// failed but we recovered". Equivalent to calling `report` with
    /// `level: .warning`.
    func warning(kind: String, message: String, error: Error? = nil) {
        report(kind: kind, level: .warning, message: message, error: error)
    }

    /// Convenience for criticals. Equivalent to `report(level:
    /// .critical, ...)`.
    func critical(kind: String, message: String, error: Error? = nil) {
        report(kind: kind, level: .critical, message: message, error: error)
    }

    /// Dismisses the prominent banner without touching `recentEvents`.
    /// Called from the UI when the user taps the dismiss affordance.
    func clearCritical() {
        lastCritical = nil
    }

    /// Wipes the entire buffer. Intended for the "Clear" button in the
    /// diagnostics panel; not meant for routine use.
    func clearAll() {
        recentEvents.removeAll()
        lastCritical = nil
    }

    /// Builds a plain-text dump of the recent buffer for the user to
    /// paste into an email, GitHub issue, or chat. Includes app build
    /// metadata at the top so the recipient can tell which version
    /// produced the events without asking. Timestamps render in UTC
    /// to match what the user would see in `log show` output.
    ///
    /// Format:
    ///
    /// ```
    /// Tempo for Claude diagnostics
    /// App: 1.2.10 (build 16809984)
    /// Bundle: com.tenondev.tempo.claude
    /// OS: macOS 26.0
    /// Captured: 2026-05-15T17:46:30Z
    ///
    /// 2026-05-15T17:46:30Z [critical] icloud.unavailable
    ///   iCloud is unavailable. Usage won't sync across your devices.
    ///   detail: <NSError ...>
    /// 2026-05-15T17:45:50Z [warning] icloud.write.usage
    ///   ...
    /// ```
    ///
    /// When the buffer is empty the dump still includes the header so
    /// the recipient can verify the panel was checked.
    func formatForClipboard() -> String {
        var lines: [String] = []
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let bundleId = bundle.bundleIdentifier ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString

        lines.append("Tempo for Claude diagnostics")
        lines.append("App: \(version) (build \(build))")
        lines.append("Bundle: \(bundleId)")
        lines.append("OS: \(os)")
        lines.append("Captured: \(Self.utcFormatter.string(from: Date()))")
        lines.append("")

        if recentEvents.isEmpty {
            lines.append("(no events recorded)")
        } else {
            // Newest first so the most relevant entry is at the top.
            for event in recentEvents.reversed() {
                let timestamp = Self.utcFormatter.string(from: event.timestamp)
                lines.append("\(timestamp) [\(event.level.rawValue)] \(event.kind)")
                lines.append("  \(event.message)")
                if let detail = event.detail {
                    // Indent multi-line detail so the structure stays
                    // readable when pasted into a monospace context.
                    let indented = detail
                        .split(separator: "\n", omittingEmptySubsequences: false)
                        .map { "  detail: \($0)" }
                        .joined(separator: "\n          ")
                    lines.append(indented)
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    private static let utcFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
