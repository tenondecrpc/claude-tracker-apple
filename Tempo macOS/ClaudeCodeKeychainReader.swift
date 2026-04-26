import Foundation

// MARK: - ClaudeCodeKeychainReader

/// Reads OAuth tokens from the Claude Code CLI's macOS Keychain entry.
/// Service: "Claude Code-credentials", Account: $USER
enum ClaudeCodeKeychainReader {

    private static let serviceName = "Claude Code-credentials"

    struct CLITokens: Codable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: TimeInterval?
        let scopes: [String]
        let subscriptionType: String?
    }

    struct SecureStorageData: Codable {
        let claudeAiOauth: CLITokens?
    }

    /// Returns the CLI OAuth tokens if available in the macOS Keychain.
    static func loadTokens() -> CLITokens? {
        let account = NSUserName()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = [
            "find-generic-password",
            "-a", account,
            "-w",
            "-s", serviceName,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let jsonString = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }

            let jsonData = Data(jsonString.utf8)
            let storage = try? JSONDecoder().decode(SecureStorageData.self, from: jsonData)
            return storage?.claudeAiOauth
        } catch {
            return nil
        }
    }

    /// Returns true if valid CLI OAuth tokens exist in the keychain.
    static func hasValidSession() -> Bool {
        guard let tokens = loadTokens() else { return false }
        guard let accessToken = tokens.accessToken.isEmpty ? nil : tokens.accessToken else { return false }
        _ = accessToken
        if let expiresAt = tokens.expiresAt {
            let expiryDate = Date(timeIntervalSince1970: expiresAt / 1000.0)
            return expiryDate > Date().addingTimeInterval(60)
        }
        return true
    }
}
