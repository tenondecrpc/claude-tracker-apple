import SwiftUI

// MARK: - UsageProgressBar

struct UsageProgressBar: View {
    let progress: Double  // 0.0 to 1.0
    var height: CGFloat = 6
    var color: Color = ClaudeCodeTheme.accent

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(ClaudeCodeTheme.progressTrack)
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
                .stroke(ClaudeCodeTheme.ringTrack, lineWidth: 8)

            // Outer fill (weekly)
            Circle()
                .trim(from: 0, to: min(max(weeklyProgress, 0), 1))
                .stroke(ClaudeCodeTheme.info, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            // Inner track (session)
            Circle()
                .stroke(ClaudeCodeTheme.ringTrackInner, lineWidth: 10)
                .padding(18)

            // Inner fill (session)
            Circle()
                .trim(from: 0, to: min(max(sessionProgress, 0), 1))
                .stroke(ClaudeCodeTheme.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(18)

            Circle()
                .fill(ClaudeCodeTheme.background)
                .padding(36)

            // Center label
            if let label = centerLabel {
                Text(label)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
            }
        }
    }
}

// MARK: - SessionPillChip

struct SessionPillChip: View {
    let value: String
    let label: String
    var accentColor: Color = ClaudeCodeTheme.accent

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
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .background(ClaudeCodeTheme.surface)
        .clipShape(.rect(cornerRadius: 8))
    }
}

// MARK: - BurnRateCard

struct BurnRateCard: View {
    let rate: Double
    let resetCountdown: String
    let extraUsage: ExtraUsage?

    private var onTrack: Bool { rate < 20 }
    private var statusColor: Color { onTrack ? ClaudeCodeTheme.success : ClaudeCodeTheme.warning }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text("\(onTrack ? "On track" : "High burn") · \(String(format: "%.1f", rate))%/hr")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
            }

            Text(resetCountdown)
                .font(.footnote)
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if let extra = extraUsage, extra.isEnabled,
               let used = extra.usedCreditsAmount, let limit = extra.monthlyLimitAmount {
                Divider()
                    .overlay(ClaudeCodeTheme.progressTrack)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Extra Usage")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    Text("\(ExtraUsage.formatUSD(used)) / \(ExtraUsage.formatUSD(limit))")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    UsageProgressBar(
                        progress: (extra.utilization ?? 0) / 100.0,
                        height: 4,
                        color: ClaudeCodeTheme.info
                    )
                }
            }
        }
        .padding(12)
        .background(ClaudeCodeTheme.card)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(ClaudeCodeTheme.progressTrack.opacity(0.65), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 12))
    }
}

// MARK: - MenuActionRow

struct MenuActionRow: View {
    let icon: String
    let label: String
    var subtitle: String? = nil
    var iconColor: Color = ClaudeCodeTheme.textSecondary
    var labelColor: Color = ClaudeCodeTheme.textPrimary
    var isDestructive: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isDestructive ? ClaudeCodeTheme.error : iconColor)
                    .frame(width: 16, alignment: .center)

                if let subtitle {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label)
                            .font(.system(size: 13))
                            .foregroundStyle(isDestructive ? ClaudeCodeTheme.error : labelColor)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(ClaudeCodeTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                } else {
                    Text(label)
                        .font(.system(size: 13))
                        .foregroundStyle(isDestructive ? ClaudeCodeTheme.error : labelColor)
                }

                Spacer()
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? ClaudeCodeTheme.surface : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.1), value: isHovered)
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
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Spacer()
                // Service status dot
                Circle()
                    .fill(dotColor)
                    .frame(width: serviceState == .operational ? 8 : 9, height: serviceState == .operational ? 8 : 9)
                    .opacity(serviceState == .operational ? 0.4 : 1.0)
                if let onRefresh {
                    Button {
                        guard !isPolling else { return }
                        onRefresh()
                    } label: {
                        if isPolling {
                            ProgressView()
                                .controlSize(.small)
                                .tint(ClaudeCodeTheme.textSecondary)
                                .frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 17)
            .padding(.vertical, 12)
            Divider()
                .overlay(ClaudeCodeTheme.progressTrack)
            if serviceState != .operational {
                ServiceStatusBannerView(state: serviceState)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 8)
            }
        }
    }

    private var dotColor: Color {
        switch serviceState {
        case .operational: return ClaudeCodeTheme.success
        case .degraded:    return ClaudeCodeTheme.warning
        case .majorOutage: return ClaudeCodeTheme.error
        case .stale:       return ClaudeCodeTheme.warning
        case .unavailable: return ClaudeCodeTheme.textSecondary
        }
    }
}

// MARK: - ServiceStatusBannerView

struct ServiceStatusBannerView: View {
    let state: ServiceHealthState

    var body: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(bannerColor)
                .frame(width: 3)
                .clipShape(.rect(cornerRadius: 1.5))

            Image(systemName: bannerIcon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(bannerColor)

            Text(bannerLabel)
                .font(.caption.weight(.medium))
                .foregroundStyle(ClaudeCodeTheme.textPrimary)
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(ClaudeCodeTheme.card)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(bannerColor.opacity(0.35), lineWidth: 1)
        }
        .clipShape(.rect(cornerRadius: 10))
    }

    private var bannerColor: Color {
        switch state {
        case .majorOutage: return ClaudeCodeTheme.error
        case .degraded, .stale: return ClaudeCodeTheme.warning
        case .unavailable: return ClaudeCodeTheme.textSecondary
        case .operational: return .clear
        }
    }

    private var bannerIcon: String {
        switch state {
        case .majorOutage: return "exclamationmark.triangle.fill"
        case .degraded:    return "exclamationmark.circle.fill"
        case .stale:       return "clock.badge.exclamationmark.fill"
        case .unavailable: return "questionmark.circle.fill"
        case .operational: return ""
        }
    }

    private var bannerLabel: String {
        switch state {
        case .majorOutage: return "Major outage · claude.ai"
        case .degraded:    return "Degraded performance · claude.ai"
        case .stale:       return "Status data may be outdated"
        case .unavailable: return "Service status unavailable"
        case .operational: return ""
        }
    }
}
