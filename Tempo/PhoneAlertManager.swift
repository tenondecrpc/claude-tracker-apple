import Foundation
import UserNotifications

final class PhoneAlertManager: NSObject {
    private enum DefaultsKey {
        static let lastAlertedSessionID = "phoneAlert.lastAlertedSessionID"
    }

    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private var hasRequestedAuthorization = false

    private static func debugPrint(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Tempo iOS] \(message())")
        #endif
    }

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
        Self.debugPrint(
            "PhoneAlertManager syncAuthorization enabledInPreferences=\(enabledInPreferences) hasRequestedAuthorization=\(hasRequestedAuthorization)"
        )
        DevLog.trace("AlertTrace", "PhoneAlertManager syncAuthorization enabledInPreferences=\(enabledInPreferences) hasRequestedAuthorization=\(hasRequestedAuthorization)")
        center.getNotificationSettings { settings in
            Self.debugPrint(
                "PhoneAlertManager settings authorizationStatus=\(settings.authorizationStatus.rawValue) alertSetting=\(settings.alertSetting.rawValue) soundSetting=\(settings.soundSetting.rawValue) badgeSetting=\(settings.badgeSetting.rawValue)"
            )
            DevLog.trace(
                "AlertTrace",
                "PhoneAlertManager current authorization settings authorizationStatus=\(settings.authorizationStatus.rawValue) alertSetting=\(settings.alertSetting.rawValue) soundSetting=\(settings.soundSetting.rawValue) badgeSetting=\(settings.badgeSetting.rawValue)"
            )
        }
        if enabledInPreferences, !hasRequestedAuthorization {
            hasRequestedAuthorization = true
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    Self.debugPrint("PhoneAlertManager authorization request failed error=\(error.localizedDescription)")
                    print("[PhoneAlert] authorization request failed: \(error)")
                } else {
                    Self.debugPrint("PhoneAlertManager authorization request granted=\(granted)")
                    print("[PhoneAlert] authorization granted: \(granted)")
                }
            }
        }
    }

    func notifySessionCompletion(for session: SessionInfo, enabledInPreferences: Bool) {
        Self.debugPrint(
            "PhoneAlertManager notifySessionCompletion sessionId=\(session.sessionId) enabledInPreferences=\(enabledInPreferences) lastAlertedSessionID=\(lastAlertedSessionID ?? "nil")"
        )
        DevLog.trace(
            "AlertTrace",
            "PhoneAlertManager received session id=\(session.sessionId) enabledInPreferences=\(enabledInPreferences) lastAlertedSessionID=\(lastAlertedSessionID ?? "nil")"
        )
        guard enabledInPreferences else {
            Self.debugPrint("PhoneAlertManager skipped session \(session.sessionId) because preference is disabled")
            DevLog.trace("AlertTrace", "PhoneAlertManager skipped session id=\(session.sessionId) because iPhone alerts are disabled in preferences")
            return
        }
        guard lastAlertedSessionID != session.sessionId else {
            Self.debugPrint("PhoneAlertManager skipped duplicate session \(session.sessionId)")
            DevLog.trace("AlertTrace", "PhoneAlertManager skipped duplicate session id=\(session.sessionId)")
            return
        }

        logPendingRequests(prefix: "before schedule attempt")

        center.getNotificationSettings { [weak self] settings in
            guard let self else { return }
            Self.debugPrint(
                "PhoneAlertManager scheduling check sessionId=\(session.sessionId) authorizationStatus=\(settings.authorizationStatus.rawValue) alertSetting=\(settings.alertSetting.rawValue) soundSetting=\(settings.soundSetting.rawValue)"
            )
            DevLog.trace(
                "AlertTrace",
                "PhoneAlertManager notification settings for session id=\(session.sessionId) authorizationStatus=\(settings.authorizationStatus.rawValue) alertSetting=\(settings.alertSetting.rawValue) soundSetting=\(settings.soundSetting.rawValue)"
            )
            guard Self.isNotificationsEnabled(settings.authorizationStatus) else {
                Self.debugPrint("PhoneAlertManager authorization missing for session \(session.sessionId)")
                print("[PhoneAlert] authorization missing; skipping session id=\(session.sessionId)")
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Claude Code Task Finished"
            content.body = Self.notificationBody(for: session)
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
                if let error {
                    Self.debugPrint("PhoneAlertManager failed scheduling session \(session.sessionId) error=\(error.localizedDescription)")
                    print("[PhoneAlert] failed to schedule notification for session id=\(session.sessionId): \(error)")
                    return
                }

                self.lastAlertedSessionID = session.sessionId
                Self.debugPrint(
                    "PhoneAlertManager scheduled local notification identifier=\(Self.notificationIdentifier(for: session)) body=\(content.body)"
                )
                DevLog.trace(
                    "AlertTrace",
                    "PhoneAlertManager scheduled notification identifier=\(Self.notificationIdentifier(for: session)) body=\(content.body)"
                )
                self.logPendingRequests(prefix: "after schedule success")
                print("[PhoneAlert] scheduled session completion notification id=\(session.sessionId)")
            }
        }
    }

    private static func isNotificationsEnabled(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional
    }

    private static func notificationIdentifier(for session: SessionInfo) -> String {
        "session-complete.\(session.sessionId)"
    }

    private static func notificationBody(for session: SessionInfo) -> String {
        "\(formatTokens(session.inputTokens + session.outputTokens)) in \(formatDuration(session.durationSeconds))"
    }

    private static func formatTokens(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let value = formatter.string(from: NSNumber(value: count)) ?? "\(count)"
        return "\(value) tokens"
    }

    private static func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60

        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private var lastAlertedSessionID: String? {
        get { defaults.string(forKey: DefaultsKey.lastAlertedSessionID) }
        set { defaults.setValue(newValue, forKey: DefaultsKey.lastAlertedSessionID) }
    }

    private func logPendingRequests(prefix: String) {
        center.getPendingNotificationRequests { requests in
            let identifiers = requests.map(\.identifier).sorted()
            Self.debugPrint("PhoneAlertManager pending requests \(prefix) count=\(requests.count) identifiers=\(identifiers)")
            DevLog.trace(
                "AlertTrace",
                "PhoneAlertManager pending requests \(prefix) count=\(requests.count) identifiers=\(identifiers)"
            )
        }
    }
}

extension PhoneAlertManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        Self.debugPrint(
            "PhoneAlertManager willPresent identifier=\(notification.request.identifier) type=\(userInfo["type"] as? String ?? "unknown")"
        )
        DevLog.trace(
            "AlertTrace",
            "PhoneAlertManager willPresent identifier=\(notification.request.identifier) type=\(userInfo["type"] as? String ?? "unknown")"
        )
        guard userInfo["type"] as? String == "SessionInfo" else {
            completionHandler([.sound, .banner, .list])
            return
        }

        completionHandler([.sound, .banner, .list])
    }
}
