import Foundation

enum DevLog {
    static var isEnabled: Bool {
        #if DEBUG
        true
        #else
        ProcessInfo.processInfo.environment["TEMPO_DEV_LOGS"] == "1"
        #endif
    }

    static func trace(_ category: String, _ message: @autoclosure () -> String) {
        guard isEnabled else { return }
        print("[\(category)] \(message())")
    }
}
