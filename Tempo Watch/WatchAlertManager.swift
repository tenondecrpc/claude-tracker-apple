import Foundation
import UserNotifications

final class WatchAlertManager: NSObject {
    private enum DefaultsKey {
        static let lastAlertedSessionID = "watchAlert.lastAlertedSessionID"
    }

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var hasRequestedAuthorization = false

    var onAlertStateChange: ((Bool) -> Void)?

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
        super.init()
        center.delegate = self
    }

    func syncAuthorization(enabledInPreferences: Bool) {
        if enabledInPreferences, !hasRequestedAuthorization {
            hasRequestedAuthorization = true
            center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
                self?.refreshAlertState(enabledInPreferences: enabledInPreferences)
            }
            return
        }

        refreshAlertState(enabledInPreferences: enabledInPreferences)
    }

    func refreshAlertState(enabledInPreferences: Bool) {
        center.getNotificationSettings { [weak self] settings in
            let isEnabled = enabledInPreferences && Self.isNotificationsEnabled(settings.authorizationStatus)
            DispatchQueue.main.async {
                self?.onAlertStateChange?(isEnabled)
            }
        }
    }

    func notifySessionCompletion(for session: SessionInfo, enabledInPreferences: Bool) {
        guard enabledInPreferences else {
            refreshAlertState(enabledInPreferences: enabledInPreferences)
            return
        }
        guard lastAlertedSessionID != session.sessionId else { return }

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }

            let isEnabled = enabledInPreferences && Self.isNotificationsEnabled(settings.authorizationStatus)
            DispatchQueue.main.async { [weak self] in
                self?.onAlertStateChange?(isEnabled)
            }

            guard isEnabled else {
                return
            }

            let presentation = session.notificationPresentation()
            let content = UNMutableNotificationContent()
            content.title = presentation.title
            content.subtitle = presentation.subtitle
            content.body = presentation.body
            content.sound = .default
            content.userInfo = [
                "type": "SessionInfo",
                "sessionId": session.sessionId,
            ]

            let request = UNNotificationRequest(
                identifier: Self.notificationIdentifier(for: session),
                content: content,
                trigger: nil
            )

            self.center.add(request) { error in
                if error != nil {
                    return
                }

                self.lastAlertedSessionID = session.sessionId
            }
        }
    }

    private static func isNotificationsEnabled(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    private static func notificationIdentifier(for session: SessionInfo) -> String {
        "session-complete.\(session.sessionId)"
    }

    private var lastAlertedSessionID: String? {
        get { defaults.string(forKey: DefaultsKey.lastAlertedSessionID) }
        set { defaults.setValue(newValue, forKey: DefaultsKey.lastAlertedSessionID) }
    }
}

extension WatchAlertManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        guard userInfo["type"] as? String == "SessionInfo" else {
            completionHandler([.sound, .banner, .list])
            return
        }

        completionHandler([.sound, .banner, .list])
    }
}
