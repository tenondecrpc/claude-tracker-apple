import Foundation

struct SessionNotificationPresentation {
    let title: String
    let subtitle: String
    let body: String
}

extension SessionInfo {
    func notificationPresentation(now: Date = Date()) -> SessionNotificationPresentation {
        let projectName = Self.projectDisplayName(from: sessionId)
        let title: String
        if let projectName {
            title = "\(Self.truncated(projectName, maxLength: 48)) finished"
        } else {
            title = "Claude Code task finished"
        }

        return SessionNotificationPresentation(
            title: title,
            subtitle: metricsSummary,
            body: Self.completionTimingSummary(for: timestamp, now: now)
        )
    }

    var metricsSummary: String {
        [
            Self.formatTokens(inputTokens + outputTokens),
            Self.formatCost(costUSD),
            Self.formatDuration(durationSeconds)
        ].joined(separator: " • ")
    }

    private static let genericPathTokens: Set<String> = [
        "code",
        "desktop",
        "developer",
        "developers",
        "documents",
        "home",
        "personal",
        "project",
        "projects",
        "repo",
        "repos",
        "source",
        "src",
        "user",
        "users",
        "work",
        "workspace",
        "workspaces"
    ]

    private static let tokenFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()

    private static func projectDisplayName(from sessionId: String) -> String? {
        let rawProject = sessionId.split(
            separator: ":",
            maxSplits: 1,
            omittingEmptySubsequences: false
        ).first.map(String.init)

        guard let rawProject, !rawProject.isEmpty else { return nil }

        let decoded = rawProject.removingPercentEncoding ?? rawProject

        if decoded.contains("/") || decoded.contains("\\") {
            let separators = CharacterSet(charactersIn: "/\\")
            let parts = decoded
                .components(separatedBy: separators)
                .filter { !$0.isEmpty }
            return parts.last.map { truncated($0, maxLength: 48) }
        }

        let tokens = decoded
            .split(separator: "-", omittingEmptySubsequences: true)
            .map(String.init)

        guard !tokens.isEmpty else {
            return truncated(decoded, maxLength: 48)
        }

        if let lastGenericIndex = tokens.lastIndex(where: { genericPathTokens.contains($0.lowercased()) }) {
            let nextIndex = tokens.index(after: lastGenericIndex)
            if nextIndex < tokens.endIndex {
                return truncated(tokens[nextIndex...].joined(separator: "-"), maxLength: 48)
            }
        }

        return truncated(decoded, maxLength: 48)
    }

    private static func completionTimingSummary(for timestamp: Date, now: Date) -> String {
        let finishedAt = finishedAtFormatter.string(from: timestamp)
        let delaySeconds = now.timeIntervalSince(timestamp)

        guard delaySeconds >= 90 else {
            return "Finished at \(finishedAt)"
        }

        let relative = relativeFormatter.localizedString(for: timestamp, relativeTo: now)
        return "Finished \(relative) at \(finishedAt)"
    }

    private static func formatTokens(_ count: Int) -> String {
        if count >= 1000 {
            let thousands = Double(count) / 1000.0
            return String(format: "%.1fK tokens", thousands)
        }

        let formatted = tokenFormatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(formatted) tokens"
    }

    private static func formatCost(_ usd: Double) -> String {
        String(format: "$%.2f", usd)
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s run"
        }

        return "\(remainingSeconds)s run"
    }

    private static func truncated(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return "\(text.prefix(maxLength - 3))..."
    }

    private static let finishedAtFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
