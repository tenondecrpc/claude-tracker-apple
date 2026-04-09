import Foundation
import SwiftUI

@Observable
@MainActor
final class MacSettingsStore {
    private enum Key {
        static let launchAtLogin = "mac.settings.launchAtLogin"
        static let show5hPercentage = "mac.settings.show5hPercentage"
        static let show5hResetTime = "mac.settings.show5hResetTime"
        static let show7dPercentage = "mac.settings.show7dPercentage"
        static let show7dResetTime = "mac.settings.show7dResetTime"
        static let showExtraUsageCredits = "mac.settings.showExtraUsageCredits"
        static let use24HourTime = "mac.settings.use24HourTime"
        static let serviceStatusMonitoring = "mac.settings.serviceStatusMonitoring"
        static let syncHistoryViaICloud = "mac.settings.syncHistoryViaICloud"
        static let autoCheckForUpdates = "mac.settings.autoCheckForUpdates"
        static let appearanceMode = "mac.settings.appearanceMode"
    }

    var onServiceStatusMonitoringChanged: ((Bool) -> Void)?
    var onSyncHistoryViaICloudChanged: ((Bool) -> Void)?

    var launchAtLogin: Bool {
        didSet {
            persist(launchAtLogin, forKey: Key.launchAtLogin)
        }
    }

    var show5hPercentage: Bool {
        didSet {
            persist(show5hPercentage, forKey: Key.show5hPercentage)
        }
    }

    var show5hResetTime: Bool {
        didSet {
            persist(show5hResetTime, forKey: Key.show5hResetTime)
        }
    }

    var show7dPercentage: Bool {
        didSet {
            persist(show7dPercentage, forKey: Key.show7dPercentage)
        }
    }

    var show7dResetTime: Bool {
        didSet {
            persist(show7dResetTime, forKey: Key.show7dResetTime)
        }
    }

    var showExtraUsageCredits: Bool {
        didSet {
            persist(showExtraUsageCredits, forKey: Key.showExtraUsageCredits)
        }
    }

    var use24HourTime: Bool {
        didSet {
            persist(use24HourTime, forKey: Key.use24HourTime)
        }
    }

    var serviceStatusMonitoring: Bool {
        didSet {
            persist(serviceStatusMonitoring, forKey: Key.serviceStatusMonitoring)
            if !isHydrating {
                onServiceStatusMonitoringChanged?(serviceStatusMonitoring)
            }
        }
    }

    var syncHistoryViaICloud: Bool {
        didSet {
            persist(syncHistoryViaICloud, forKey: Key.syncHistoryViaICloud)
            if !isHydrating {
                onSyncHistoryViaICloudChanged?(syncHistoryViaICloud)
            }
        }
    }

    var autoCheckForUpdates: Bool {
        didSet {
            persist(autoCheckForUpdates, forKey: Key.autoCheckForUpdates)
        }
    }

    var appearanceMode: AppearanceMode {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Key.appearanceMode)
        }
    }

    private let defaults: UserDefaults
    private var isHydrating = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isHydrating = true

        launchAtLogin = defaults.object(forKey: Key.launchAtLogin) != nil
            ? defaults.bool(forKey: Key.launchAtLogin)
            : false

        show5hPercentage = defaults.object(forKey: Key.show5hPercentage) != nil
            ? defaults.bool(forKey: Key.show5hPercentage)
            : false

        show5hResetTime = defaults.object(forKey: Key.show5hResetTime) != nil
            ? defaults.bool(forKey: Key.show5hResetTime)
            : false

        show7dPercentage = defaults.object(forKey: Key.show7dPercentage) != nil
            ? defaults.bool(forKey: Key.show7dPercentage)
            : false

        show7dResetTime = defaults.object(forKey: Key.show7dResetTime) != nil
            ? defaults.bool(forKey: Key.show7dResetTime)
            : false

        showExtraUsageCredits = defaults.object(forKey: Key.showExtraUsageCredits) != nil
            ? defaults.bool(forKey: Key.showExtraUsageCredits)
            : false

        use24HourTime = defaults.object(forKey: Key.use24HourTime) != nil
            ? defaults.bool(forKey: Key.use24HourTime)
            : true

        serviceStatusMonitoring = defaults.object(forKey: Key.serviceStatusMonitoring) != nil
            ? defaults.bool(forKey: Key.serviceStatusMonitoring)
            : true

        syncHistoryViaICloud = defaults.object(forKey: Key.syncHistoryViaICloud) != nil
            ? defaults.bool(forKey: Key.syncHistoryViaICloud)
            : true

        autoCheckForUpdates = defaults.object(forKey: Key.autoCheckForUpdates) != nil
            ? defaults.bool(forKey: Key.autoCheckForUpdates)
            : true

        if let raw = defaults.string(forKey: Key.appearanceMode),
           let mode = AppearanceMode(rawValue: raw) {
            appearanceMode = mode
        } else {
            appearanceMode = .dark
        }

        isHydrating = false
    }

    func updateLaunchAtLoginFromSystem(_ enabled: Bool) {
        let oldHydrating = isHydrating
        isHydrating = true
        launchAtLogin = enabled
        isHydrating = oldHydrating
    }

    private func persist(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    var preferredColorScheme: ColorScheme? { appearanceMode.colorScheme }
}
