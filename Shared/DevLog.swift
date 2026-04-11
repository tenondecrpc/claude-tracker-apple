import Foundation

enum DevLog {
    nonisolated static func trace(_ category: String, _ message: @autoclosure () -> String) {
        _ = category
        _ = message
    }
}
