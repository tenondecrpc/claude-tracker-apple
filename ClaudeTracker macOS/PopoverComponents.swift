import SwiftUI

// MARK: - UsageProgressBar

struct UsageProgressBar: View {
    let progress: Double  // 0.0 to 1.0
    var height: CGFloat = 6
    var color: Color = TempoTheme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(TempoTheme.progressTrack)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(color)
                    .frame(width: max(height, geo.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - UsageRingView

struct UsageRingView: View {
    let sessionProgress: Double   // 0.0 to 1.0
    let weeklyProgress: Double    // 0.0 to 1.0
    var centerLabel: String? = nil

    var body: some View {
        ZStack {
            // Outer track (weekly)
            Circle()
                .stroke(TempoTheme.progressTrack, lineWidth: 8)

            // Outer fill (weekly)
            Circle()
                .trim(from: 0, to: min(max(weeklyProgress, 0), 1))
                .stroke(TempoTheme.info, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Inner track (session)
            Circle()
                .stroke(TempoTheme.progressTrack, lineWidth: 10)
                .padding(18)

            // Inner fill (session)
            Circle()
                .trim(from: 0, to: min(max(sessionProgress, 0), 1))
                .stroke(TempoTheme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(18)

            // Center label
            if let label = centerLabel {
                Text(label)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(TempoTheme.textPrimary)
            }
        }
    }
}

// MARK: - SessionPillChip

struct SessionPillChip: View {
    let value: String
    let label: String
    var accentColor: Color = TempoTheme.accent

    var body: some View {
        HStack(spacing: 0) {
            // Left-edge accent stripe
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
                .clipShape(.rect(cornerRadius: 1.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(TempoTheme.textPrimary)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(TempoTheme.textSecondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(TempoTheme.surface)
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - BurnRateCard

struct BurnRateCard: View {
    let rate: Double
    let resetCountdown: String
    let extraUsage: ExtraUsage?

    private var onTrack: Bool { rate < 20 }
    private var statusColor: Color { onTrack ? TempoTheme.success : TempoTheme.warning }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("\(onTrack ? "On track" : "High burn") · \(String(format: "%.1f", rate))%/hr")
                    .font(.callout)
                    .foregroundStyle(TempoTheme.textPrimary)
            }

            Text(resetCountdown)
                .font(.footnote)
                .foregroundStyle(TempoTheme.textSecondary)

            if let extra = extraUsage, extra.isEnabled,
               let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                Divider()
                    .overlay(TempoTheme.progressTrack)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Extra Usage")
                        .font(.footnote)
                        .foregroundStyle(TempoTheme.textSecondary)
                    Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(TempoTheme.textPrimary)
                    UsageProgressBar(
                        progress: (extra.utilization ?? 0) / 100.0,
                        height: 4,
                        color: TempoTheme.info
                    )
                }
            }
        }
        .padding(12)
        .background(TempoTheme.card)
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - MenuBarHeaderView

struct MenuBarHeaderView: View {
    var onRefresh: (() -> Void)? = nil
    var isPolling: Bool = false
    var serviceState: ServiceHealthState = .operational

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Tempo")
                    .font(.headline)
                    .foregroundStyle(TempoTheme.textPrimary)
                Spacer()
                // Service status dot
                Circle()
                    .fill(colorForServiceState(serviceState))
                    .frame(width: 8, height: 8)
                    .opacity(serviceState == .operational ? 0.4 : 1.0)
                if let onRefresh {
                    Button {
                        guard !isPolling else { return }
                        onRefresh()
                    } label: {
                        if isPolling {
                            ProgressView()
                                .controlSize(.small)
                                .tint(TempoTheme.textSecondary)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(TempoTheme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            Divider()
                .overlay(TempoTheme.progressTrack)
        }
    }

    private func colorForServiceState(_ state: ServiceHealthState) -> Color {
        switch state {
        case .operational: return TempoTheme.success
        case .degraded: return TempoTheme.warning
        case .majorOutage: return TempoTheme.critical
        case .stale: return TempoTheme.warning
        case .unavailable: return TempoTheme.textSecondary
        }
    }
}
