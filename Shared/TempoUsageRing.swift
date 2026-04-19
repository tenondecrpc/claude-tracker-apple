import SwiftUI

// MARK: - UsageRingStyle

/// Shared visual criteria for the dual concentric usage rings across every
/// Tempo surface (macOS popover, iOS dashboard, watchOS main view, widgets).
///
/// All strokes, gaps, and insets are expressed as fractions of the ring
/// diameter so a 64pt card ring and a 180pt dashboard ring keep identical
/// proportions. The color tokens live here so "session" and "weekly" render
/// the same hue on every device.
enum UsageRingStyle {
    /// Outer ring (5h session). Slightly thicker so the primary, faster-changing
    /// metric reads first at a glance.
    static let outerStrokeRatio: CGFloat = 0.10

    /// Inner ring (7d weekly). Thinner to preserve visual hierarchy.
    static let innerStrokeRatio: CGFloat = 0.075

    /// Gap between the outer stroke and the inner ring.
    static let ringGapRatio: CGFloat = 0.035

    /// Inner ring inset from the outer edge of the frame.
    static var innerInsetRatio: CGFloat { outerStrokeRatio + ringGapRatio }

    static var sessionBaseColor: Color { ClaudeCodeTheme.Usage.session }
    static var weeklyBaseColor: Color { ClaudeCodeTheme.Usage.weekly }

    static func sessionColor(utilization: Double) -> Color {
        UtilizationSeverity(utilization: utilization).usageColor(normal: sessionBaseColor)
    }

    static func weeklyColor(utilization: Double) -> Color {
        UtilizationSeverity(utilization: utilization).usageColor(normal: weeklyBaseColor)
    }
}

// MARK: - TempoUsageRing

/// The single shared dual ring view. Session (5h) is the outer ring; weekly
/// (7d) is the inner ring. Optional `center` content renders inside the hole.
struct TempoUsageRing<Center: View>: View {
    let sessionProgress: Double
    let weeklyProgress: Double
    let center: () -> Center

    init(
        sessionProgress: Double,
        weeklyProgress: Double,
        @ViewBuilder center: @escaping () -> Center = { EmptyView() }
    ) {
        self.sessionProgress = sessionProgress
        self.weeklyProgress = weeklyProgress
        self.center = center
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let outerStroke = size * UsageRingStyle.outerStrokeRatio
            let innerStroke = size * UsageRingStyle.innerStrokeRatio
            let innerInset = size * UsageRingStyle.innerInsetRatio

            ZStack {
                Circle()
                    .stroke(ClaudeCodeTheme.ringTrack, lineWidth: outerStroke)

                Circle()
                    .trim(from: 0, to: Self.clamp(sessionProgress))
                    .stroke(
                        UsageRingStyle.sessionColor(utilization: sessionProgress),
                        style: StrokeStyle(lineWidth: outerStroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                Circle()
                    .stroke(ClaudeCodeTheme.ringTrackInner, lineWidth: innerStroke)
                    .padding(innerInset)

                Circle()
                    .trim(from: 0, to: Self.clamp(weeklyProgress))
                    .stroke(
                        UsageRingStyle.weeklyColor(utilization: weeklyProgress),
                        style: StrokeStyle(lineWidth: innerStroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .padding(innerInset)

                center()
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

// MARK: - TempoSingleRing

/// Single-metric ring. Uses the outer-ring stroke geometry of the shared dual
/// ring so detail cards that represent one metric (e.g. Session OR Weekly)
/// keep visual continuity with the main dashboard ring without showing an
/// unused empty track.
struct TempoSingleRing<Center: View>: View {
    let progress: Double
    let color: Color
    let center: () -> Center

    init(
        progress: Double,
        color: Color,
        @ViewBuilder center: @escaping () -> Center = { EmptyView() }
    ) {
        self.progress = progress
        self.color = color
        self.center = center
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let stroke = size * UsageRingStyle.outerStrokeRatio

            ZStack {
                Circle()
                    .stroke(ClaudeCodeTheme.ringTrack, lineWidth: stroke)

                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                center()
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
