import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - AppearanceMode

enum AppearanceMode: String, CaseIterable, Codable {
    case dark
    case light
    case system

    var displayName: String {
        switch self {
        case .dark:   return "Dark"
        case .light:  return "Light"
        case .system: return "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark:   return .dark
        case .light:  return .light
        case .system: return nil
        }
    }

    func resolved(for colorScheme: ColorScheme) -> AppearanceMode {
        switch self {
        case .dark:
            .dark
        case .light:
            .light
        case .system:
            colorScheme == .light ? .light : .dark
        }
    }

    #if os(macOS)
    var nsAppearance: NSAppearance? {
        switch self {
        case .dark:
            NSAppearance(named: .darkAqua)
        case .light:
            NSAppearance(named: .aqua)
        case .system:
            nil
        }
    }
    #endif
}

// MARK: - ClaudeCodeTheme

/// Unified design token system sourced from the official Claude Code Dark/Light palette.
///
/// On macOS/iOS, tokens resolve through platform-native dynamic color providers so they
/// automatically track the effective appearance of the hosting window or trait collection.
/// On watchOS, where dynamic providers are unavailable, they resolve through a process
/// global updated by the view tree via `setResolvedAppearanceMode`.
enum ClaudeCodeTheme {
    #if os(watchOS)
    private static var resolvedAppearanceMode: AppearanceMode = .dark

    static func setResolvedAppearanceMode(_ mode: AppearanceMode) {
        guard mode != .system else { return }
        resolvedAppearanceMode = mode
    }
    #else
    /// No-op on macOS/iOS: dynamic platform colors follow the view hierarchy's
    /// effective appearance, so no global mirror is required.
    static func setResolvedAppearanceMode(_ mode: AppearanceMode) {}
    #endif

    // MARK: Backgrounds

    static var background: Color {
        adaptive(dark: (0.0784, 0.0784, 0.0745), light: (0.9804, 0.9765, 0.9608))
    }
    static var surface: Color {
        adaptive(dark: (0.1216, 0.1137, 0.1020), light: (0.9412, 0.9333, 0.9020))
    }
    static var card: Color {
        adaptive(dark: (0.1686, 0.1647, 0.1529), light: (0.9176, 0.9059, 0.8745))
    }

    // MARK: Accent

    static var accent: Color {
        adaptive(dark: (0.7882, 0.3922, 0.2588), light: (0.8000, 0.4706, 0.3608))
    }
    static var accentLight: Color {
        adaptive(dark: (0.8510, 0.4667, 0.3412), light: (0.7882, 0.3922, 0.2588))
    }
    static var accentMuted: Color { accent.opacity(0.15) }

    // MARK: Text

    static var textPrimary: Color {
        adaptive(dark: (0.9176, 0.9059, 0.8745), light: (0.1020, 0.0980, 0.0902))
    }
    static var textSecondary: Color {
        adaptive(dark: (0.6627, 0.6392, 0.6039), light: (0.4196, 0.4000, 0.3725))
    }
    static var textTertiary: Color {
        adaptive(dark: (0.4196, 0.4000, 0.3725), light: (0.5529, 0.5294, 0.4902))
    }

    // MARK: Borders / Tracks

    static var border: Color {
        adaptive(dark: (0.2902, 0.2784, 0.2471), light: (0.8510, 0.8353, 0.8000))
    }
    static var progressTrack: Color { border }

    // MARK: Status

    static var success: Color {
        adaptive(dark: (0.6039, 0.7922, 0.5255), light: (0.1804, 0.4863, 0.2980))
    }
    static var warning: Color {
        adaptive(dark: (0.9098, 0.7882, 0.4196), light: (0.5412, 0.3843, 0.1255))
    }
    static var error: Color {
        adaptive(dark: (0.8314, 0.4588, 0.3882), light: (0.6588, 0.2941, 0.2275))
    }
    static var info: Color {
        adaptive(dark: (0.3804, 0.6667, 0.9490), light: (0.1255, 0.4980, 0.8706))
    }
    static var highlight: Color {
        adaptive(dark: (0.6078, 0.5294, 0.9608), light: (0.4157, 0.3569, 0.8000))
    }
    static var destructive: Color { error }

    // MARK: Ring Tracks

    static var ringTrack: Color {
        adaptiveRGBA(
            dark: (1.0, 1.0, 1.0, 0.15),
            light: (0.0, 0.0, 0.0, 0.10)
        )
    }
    static var ringTrackInner: Color {
        adaptiveRGBA(
            dark: (1.0, 1.0, 1.0, 0.10),
            light: (0.0, 0.0, 0.0, 0.08)
        )
    }

    // MARK: - Private Helpers

    fileprivate static func adaptive(
        dark d: (CGFloat, CGFloat, CGFloat),
        light l: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        #if os(macOS)
        return Color(dynamicNSColor(dark: d, light: l))
        #elseif canImport(UIKit) && !os(watchOS)
        return Color(dynamicUIColor(dark: d, light: l))
        #else
        let resolved = resolvedRGB(dark: d, light: l)
        return Color(red: resolved.0, green: resolved.1, blue: resolved.2)
        #endif
    }

    fileprivate static func adaptiveRGBA(
        dark d: (CGFloat, CGFloat, CGFloat, CGFloat),
        light l: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> Color {
        #if os(macOS)
        return Color(dynamicNSColor(dark: d, light: l))
        #elseif canImport(UIKit) && !os(watchOS)
        return Color(dynamicUIColor(dark: d, light: l))
        #else
        let resolved = resolvedRGBA(dark: d, light: l)
        return Color(.sRGB, red: resolved.0, green: resolved.1, blue: resolved.2, opacity: resolved.3)
        #endif
    }

    #if os(macOS)
    fileprivate static func dynamicNSColor(
        dark d: (CGFloat, CGFloat, CGFloat),
        light l: (CGFloat, CGFloat, CGFloat)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(red: d.0, green: d.1, blue: d.2, alpha: 1)
            }
            return NSColor(red: l.0, green: l.1, blue: l.2, alpha: 1)
        }
    }

    fileprivate static func dynamicNSColor(
        dark d: (CGFloat, CGFloat, CGFloat, CGFloat),
        light l: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(red: d.0, green: d.1, blue: d.2, alpha: d.3)
            }
            return NSColor(red: l.0, green: l.1, blue: l.2, alpha: l.3)
        }
    }
    #endif

    #if canImport(UIKit) && !os(watchOS)
    fileprivate static func dynamicUIColor(
        dark d: (CGFloat, CGFloat, CGFloat),
        light l: (CGFloat, CGFloat, CGFloat)
    ) -> UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: d.0, green: d.1, blue: d.2, alpha: 1)
            }
            return UIColor(red: l.0, green: l.1, blue: l.2, alpha: 1)
        }
    }

    fileprivate static func dynamicUIColor(
        dark d: (CGFloat, CGFloat, CGFloat, CGFloat),
        light l: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> UIColor {
        UIColor { traits in
            if traits.userInterfaceStyle == .dark {
                return UIColor(red: d.0, green: d.1, blue: d.2, alpha: d.3)
            }
            return UIColor(red: l.0, green: l.1, blue: l.2, alpha: l.3)
        }
    }
    #endif

    #if os(watchOS)
    private static func resolvedRGB(
        dark d: (CGFloat, CGFloat, CGFloat),
        light l: (CGFloat, CGFloat, CGFloat)
    ) -> (CGFloat, CGFloat, CGFloat) {
        resolvedAppearanceMode == .light ? l : d
    }

    private static func resolvedRGBA(
        dark d: (CGFloat, CGFloat, CGFloat, CGFloat),
        light l: (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        resolvedAppearanceMode == .light ? l : d
    }
    #endif
}

extension ClaudeCodeTheme {
    enum ServiceStatus {
        static var operational: Color { ClaudeCodeTheme.success }
        static var degraded: Color { ClaudeCodeTheme.warning }
        static var majorOutage: Color { ClaudeCodeTheme.error }
        static var stale: Color { ClaudeCodeTheme.warning }
        static var unavailable: Color { ClaudeCodeTheme.textSecondary }
    }

    enum Usage {
        static var session: Color { ClaudeCodeTheme.accent }
        static var sessionEmphasis: Color { ClaudeCodeTheme.accentLight }
        // Purple (`highlight`) from the Claude Code palette. Pairs with the
        // terracotta session accent for a warm/cool dual-ring reading.
        static var weekly: Color { ClaudeCodeTheme.highlight }
        static var warning: Color { ClaudeCodeTheme.warning }
        // A stronger warm red than the core error token so 100% usage
        // reads as a distinct limit state instead of blending with the
        // app's terracotta accent.
        static var critical: Color {
            ClaudeCodeTheme.adaptive(
                dark: (0.8980, 0.3529, 0.2902),
                light: (0.7176, 0.2314, 0.1804)
            )
        }

        #if os(macOS)
        static var menuBarWarning: NSColor {
            ClaudeCodeTheme.dynamicNSColor(
                dark: (0.9098, 0.7882, 0.4196),
                light: (0.5412, 0.3843, 0.1255)
            )
        }
        static var menuBarCritical: NSColor {
            ClaudeCodeTheme.dynamicNSColor(
                dark: (0.8980, 0.3529, 0.2902),
                light: (0.7176, 0.2314, 0.1804)
            )
        }
        #endif
    }
}
