import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - Pasteboard

/// Cross-platform clipboard helper. macOS uses `NSPasteboard.general`,
/// iOS uses `UIPasteboard.general`. watchOS has no general pasteboard
/// for third-party apps, so the watch build compiles a no-op that
/// returns `false` and callers can hide their copy affordance.
///
/// Returns `true` when the string was placed on the system clipboard so
/// callers can show a "Copied" confirmation. Returns `false` on
/// platforms without a clipboard, which keeps watchOS UI honest about
/// the lack of effect.
enum Pasteboard {
    @discardableResult
    static func copyString(_ string: String) -> Bool {
        #if canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        return pb.setString(string, forType: .string)
        #elseif canImport(UIKit) && !os(watchOS)
        UIPasteboard.general.string = string
        return true
        #else
        return false
        #endif
    }

    /// `true` on platforms that expose a writable system clipboard.
    /// Views can hide their "Copy" affordance when this is `false`
    /// (currently only watchOS).
    static var isAvailable: Bool {
        #if canImport(AppKit)
        return true
        #elseif canImport(UIKit) && !os(watchOS)
        return true
        #else
        return false
        #endif
    }
}
