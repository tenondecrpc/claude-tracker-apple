import SwiftUI
#if os(macOS)
import AppKit
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
}

// MARK: - ClaudeCodeTheme

/// Unified design token system sourced from the official Claude Code Dark/Light palette.
/// On macOS, tokens resolve adaptively based on the app's effective appearance
/// (driven by `preferredColorScheme` in the view hierarchy).
/// On watchOS and iOS, all tokens resolve to the dark palette.
enum ClaudeCodeTheme {

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
        #if os(macOS)
        adaptiveNS(dark: NSColor.white.withAlphaComponent(0.15),
                   light: NSColor.black.withAlphaComponent(0.10))
        #else
        .white.opacity(0.15)
        #endif
    }
    static var ringTrackInner: Color {
        #if os(macOS)
        adaptiveNS(dark: NSColor.white.withAlphaComponent(0.10),
                   light: NSColor.black.withAlphaComponent(0.08))
        #else
        .white.opacity(0.10)
        #endif
    }

    // MARK: - Private Helpers

    /// Returns an adaptive Color using NSColor's dynamic provider on macOS,
    /// or the dark variant on watchOS/iOS.
    private static func adaptive(
        dark d: (CGFloat, CGFloat, CGFloat),
        light l: (CGFloat, CGFloat, CGFloat)
    ) -> Color {
        #if os(macOS)
        Color(NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(red: d.0, green: d.1, blue: d.2, alpha: 1)
            } else {
                return NSColor(red: l.0, green: l.1, blue: l.2, alpha: 1)
            }
        })
        #else
        Color(red: d.0, green: d.1, blue: d.2)
        #endif
    }

    #if os(macOS)
    private static func adaptiveNS(dark d: NSColor, light l: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? d : l
        })
    }
    #endif
}
