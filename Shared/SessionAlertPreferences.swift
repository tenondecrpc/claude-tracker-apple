import Foundation

struct SessionAlertPreferences: Codable, Equatable {
    var iPhoneAlertsEnabled: Bool
    var watchAlertsEnabled: Bool

    static let `default` = SessionAlertPreferences(
        iPhoneAlertsEnabled: false,
        watchAlertsEnabled: false
    )
}
