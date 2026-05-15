import Foundation
import OSLog

enum DevLog {
    nonisolated static func trace(_ category: String, _ message: @autoclosure () -> String) {
#if DEBUG
        let subsystem = Bundle.main.bundleIdentifier ?? "com.tenondev.tempo.claude"
        let text = message()
        let logger = Logger(subsystem: subsystem, category: category)
        if category == "AuthTrace" {
            logger.notice("\(text, privacy: .private)")
        } else {
            logger.debug("\(text, privacy: .public)")
        }
#endif
    }
}
