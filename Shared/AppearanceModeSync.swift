import Foundation

enum AppearanceModeSync {
    static let fileName = "appearance-mode.json"

    // NOTE: Appearance mode is intentionally GLOBAL (app-wide), not per-account.
    // See openspec/changes/multi-account-support/design.md:
    //   "Tempo/alert-preferences.json and Tempo/appearance-mode.json stay at
    //    Tempo/ because they are intentionally global."
    // Do NOT move this file under Tempo/accounts/<id>/. A single appearance
    // mode applies to the whole app, regardless of the active account.
    static func fileURL(fileManager: FileManager = .default) -> URL {
        AlertPreferencesSync
            .trackerDirectory(fileManager: fileManager)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    static func write(
        _ appearanceMode: AppearanceMode,
        fileManager: FileManager = .default
    ) throws {
        let directory = AlertPreferencesSync.trackerDirectory(fileManager: fileManager)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(appearanceMode)
        try data.write(to: fileURL(fileManager: fileManager), options: .atomic)
    }
}
