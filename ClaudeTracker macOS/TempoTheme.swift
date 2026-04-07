import SwiftUI

// MARK: - TempoTheme
// Design tokens for the Tempo visual identity. Scoped to the macOS target.

enum TempoTheme {
    static let background    = Color(red: 0.098, green: 0.098, blue: 0.110)  // #19191C
    static let surface       = Color(red: 0.133, green: 0.133, blue: 0.149)  // #222226
    static let card          = Color(red: 0.149, green: 0.149, blue: 0.169)  // #26262B
    static let accent        = Color(red: 0.486, green: 0.302, blue: 0.929)  // #7B4DED
    static let accentLight   = Color(red: 0.608, green: 0.463, blue: 0.976)  // #9B76F9
    static let accentMuted   = Color(red: 0.486, green: 0.302, blue: 0.929).opacity(0.15)
    static let textPrimary   = Color(red: 0.933, green: 0.933, blue: 0.953)  // #EEEEEF
    static let textSecondary = Color(red: 0.533, green: 0.533, blue: 0.573)  // #888892
    static let textTertiary  = Color(red: 0.373, green: 0.373, blue: 0.408)  // #5F5F68
    static let progressTrack = Color(red: 0.200, green: 0.200, blue: 0.224)  // #333339
    static let success       = Color(red: 0.298, green: 0.761, blue: 0.553)  // #4CC28D
    static let warning       = Color(red: 0.976, green: 0.733, blue: 0.231)  // #F9BB3B
    static let critical      = Color(red: 0.937, green: 0.325, blue: 0.388)  // #EF5363
    static let info          = Color(red: 0.302, green: 0.600, blue: 0.878)  // #4D99E0
    static let destructive   = Color(red: 0.937, green: 0.325, blue: 0.388)  // #EF5363 (alias of critical)
}
