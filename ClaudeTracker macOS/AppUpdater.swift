import AppKit
import Foundation

@Observable
@MainActor
final class AppUpdater {
    private enum Constants {
        static let owner = "tenondecrpc"
        static let repository = "tempo-for-claude"
        static let lastCheckedAt = "mac.settings.updates.lastCheckedAt"
        static let automaticCheckInterval: TimeInterval = 12 * 60 * 60
    }

    var isChecking = false
    var statusMessage: String?
    var availableVersion: String?
    var downloadURL: URL?
    var lastCheckedAt: Date?

    var currentVersionDisplay: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let buildVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(shortVersion) (\(buildVersion))"
    }

    private let autoCheckEnabled: () -> Bool
    private let defaults: UserDefaults
    private let session: URLSession

    init(autoCheckEnabled: @escaping () -> Bool, defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.autoCheckEnabled = autoCheckEnabled
        self.defaults = defaults
        self.session = session
        self.lastCheckedAt = defaults.object(forKey: Constants.lastCheckedAt) as? Date
    }

    func checkOnLaunchIfNeeded() async {
        guard autoCheckEnabled() else { return }
        guard shouldRunAutomaticCheck else { return }
        await checkForUpdates(userInitiated: false)
    }

    func checkForUpdates(userInitiated: Bool) async {
        guard !isChecking else { return }

        isChecking = true
        if userInitiated {
            statusMessage = "Checking for updates..."
        }

        defer {
            isChecking = false
        }

        do {
            let release = try await fetchLatestRelease()
            persistLastCheckedAt(Date())

            if isNewerVersionAvailable(remoteTag: release.tagName) {
                availableVersion = release.displayVersion
                downloadURL = release.preferredDownloadURL
                statusMessage = "Update \(release.displayVersion) is available."
            } else {
                availableVersion = nil
                downloadURL = nil
                statusMessage = userInitiated ? "You're up to date." : nil
            }
        } catch {
            let message: String
            if error is DecodingError {
                message = "Failed to check updates: Unexpected response format from GitHub."
            } else {
                message = "Failed to check updates: \(error.localizedDescription)"
            }
            statusMessage = userInitiated ? message : nil
        }
    }

    func openLatestRelease() {
        let fallbackURL = URL(string: "https://github.com/\(Constants.owner)/\(Constants.repository)/releases")
        let targetURL = downloadURL ?? fallbackURL

        guard let targetURL else { return }
        NSWorkspace.shared.open(targetURL)
    }

    private var shouldRunAutomaticCheck: Bool {
        guard let lastCheckedAt else { return true }
        return Date().timeIntervalSince(lastCheckedAt) >= Constants.automaticCheckInterval
    }

    private func persistLastCheckedAt(_ date: Date) {
        lastCheckedAt = date
        defaults.set(date, forKey: Constants.lastCheckedAt)
    }

    private func isNewerVersionAvailable(remoteTag: String) -> Bool {
        let remoteVersion = normalizedVersion(remoteTag)
        let localVersion = normalizedVersion(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")

        return remoteVersion.compare(localVersion, options: .numeric) == .orderedDescending
    }

    private func normalizedVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.replacingOccurrences(of: "^[^0-9]+", with: "", options: .regularExpression)
        guard !withoutPrefix.isEmpty else { return trimmed }

        let numericPrefix = withoutPrefix.prefix { character in
            character.isNumber || character == "."
        }

        return numericPrefix.isEmpty ? withoutPrefix : String(numericPrefix)
    }

    private func fetchLatestRelease() async throws -> GitHubRelease {
        let url = URL(string: "https://api.github.com/repos/\(Constants.owner)/\(Constants.repository)/releases/latest")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TempoForClaudeUpdater", forHTTPHeaderField: "User-Agent")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppUpdaterError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw AppUpdaterError.httpError(code: httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(GitHubRelease.self, from: data)
    }
}

private struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        private enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }

        let name: String
        let browserDownloadURL: URL
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case assets
    }

    let tagName: String
    let htmlURL: URL
    let assets: [Asset]

    var displayVersion: String {
        let normalized = tagName.replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
        return normalized.isEmpty ? tagName : normalized
    }

    var preferredDownloadURL: URL {
        if let dmgAsset = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }) {
            return dmgAsset.browserDownloadURL
        }
        return htmlURL
    }
}

private enum AppUpdaterError: LocalizedError {
    case invalidResponse
    case httpError(code: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Unexpected response from GitHub."
        case let .httpError(code):
            return "GitHub API returned status \(code)."
        }
    }
}
