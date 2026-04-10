import Foundation

// MARK: - StoredCredentials

struct StoredCredentials: Codable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var scopes: [String]
}

// MARK: - CredentialStore

enum CredentialStore {

    private static var credentialsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/tempo-for-claude/credentials.json")
    }

    static func load() -> StoredCredentials? {
        let url = credentialsURL
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StoredCredentials.self, from: data)
    }

    static func save(_ credentials: StoredCredentials) throws {
        let url = credentialsURL
        let dir = url.deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(credentials)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func delete() {
        try? FileManager.default.removeItem(at: credentialsURL)
    }

    /// Returns true if the credentials have a non-expired access token (with a 60s buffer).
    static func isValid(_ credentials: StoredCredentials) -> Bool {
        credentials.expiresAt > Date().addingTimeInterval(60)
    }
}
