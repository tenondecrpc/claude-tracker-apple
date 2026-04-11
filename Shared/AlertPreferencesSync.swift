import Foundation

enum AlertPreferencesSync {
    static let fileName = "alert-preferences.json"

    static func trackerDirectory(fileManager: FileManager = .default) -> URL {
        if let containerURL = fileManager.url(forUbiquityContainerIdentifier: TempoICloud.containerIdentifier) {
            return containerURL.appendingPathComponent("Documents/Tempo", isDirectory: true)
        }

        #if os(macOS)
        return URL.homeDirectory
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Tempo", isDirectory: true)
        #else
        let fallbackDirectory =
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        return fallbackDirectory.appendingPathComponent("Tempo", isDirectory: true)
        #endif
    }

    static func fileURL(fileManager: FileManager = .default) -> URL {
        trackerDirectory(fileManager: fileManager).appendingPathComponent(fileName, isDirectory: false)
    }

    static func write(
        _ preferences: SessionAlertPreferences,
        fileManager: FileManager = .default
    ) throws {
        let directory = trackerDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(preferences)
        try data.write(to: fileURL(fileManager: fileManager), options: .atomic)
        DevLog.trace(
            "AlertTrace",
            "AlertPreferencesSync wrote file path=\(fileURL(fileManager: fileManager).path) iPhone=\(preferences.iPhoneAlertsEnabled) watch=\(preferences.watchAlertsEnabled)"
        )
    }
}
