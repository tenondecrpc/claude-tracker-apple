import SwiftUI

// MARK: - DiagnosticsBannerView

/// Subtle, dismissible banner that surfaces the most recent critical
/// `DiagnosticEvent` from `DiagnosticsCenter.shared`. Renders nothing
/// when there is no active critical event so callers can drop it into
/// any layout without a conditional wrapper.
///
/// Visual rationale: warnings inside the diagnostics panel use the same
/// row treatment as informational messages so the user is not flooded
/// with attention-getting yellows/reds for recoverable failures. The
/// banner is reserved for criticals because those are the failures
/// that the user can actually do something about (sign back into iCloud,
/// reinstall the widget, etc).
struct DiagnosticsBannerView: View {
    @Environment(DiagnosticsCenter.self) private var diagnostics

    var body: some View {
        if let event = diagnostics.lastCritical {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ClaudeCodeTheme.warning)
                Text(event.message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button {
                    diagnostics.clearCritical()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        .padding(4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notice")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                ClaudeCodeTheme.warning.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(ClaudeCodeTheme.warning.opacity(0.4), lineWidth: 0.5)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Tempo notice: \(event.message)")
        }
    }
}
