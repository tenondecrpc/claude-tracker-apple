import Foundation
import ServiceManagement

@Observable
@MainActor
final class LaunchAtLoginManager {
    var isSupportedInstallLocation = false
    var isEnabled = false
    var helperMessage: String?

    init() {
        refresh()
    }

    func refresh() {
        isSupportedInstallLocation = Self.isSupportedInstallLocation()
        if !isSupportedInstallLocation {
            isEnabled = false
            helperMessage = "Install the app in Applications to manage launch at login."
            return
        }

        isEnabled = SMAppService.mainApp.status == .enabled
        helperMessage = nil
    }

    func setEnabled(_ enabled: Bool) {
        guard isSupportedInstallLocation else {
            helperMessage = "Install the app in Applications to manage launch at login."
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = SMAppService.mainApp.status == .enabled
            helperMessage = nil
        } catch {
            isEnabled = SMAppService.mainApp.status == .enabled
            helperMessage = "Could not update launch at login."
        }
    }

    static func isSupportedInstallLocation(bundleURL: URL = Bundle.main.bundleURL) -> Bool {
        let appPath = bundleURL.standardizedFileURL.path
        let userAppsPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications")
            .path
        return appPath.hasPrefix("/Applications/") || appPath.hasPrefix(userAppsPath + "/")
    }
}
