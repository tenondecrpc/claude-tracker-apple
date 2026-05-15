import SwiftUI

// MARK: - DiagnosticsRecentEventsList

/// Compact list of the most recent `DiagnosticEvent`s reported on this
/// device, intended for the diagnostics card in Preferences / Settings.
/// Renders a friendly empty-state when the buffer is empty so the card
/// is never blank.
///
/// Reads from `DiagnosticsCenter.shared` via the SwiftUI environment;
/// the host scene must inject `.environment(DiagnosticsCenter.shared)`
/// once at the top of its scene tree.
struct DiagnosticsRecentEventsList: View {
    @Environment(DiagnosticsCenter.self) private var diagnostics

    /// Tracks the transient "Copied" confirmation that replaces the
    /// Copy button label for two seconds after a successful copy.
    /// State lives on the list (not the button) so the timer is
    /// cancelled correctly when the user navigates away.
    @State private var didCopy = false
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if diagnostics.recentEvents.isEmpty {
                emptyState
                // No actions when there's nothing to act on. The empty
                // state itself communicates "all good"; offering Copy
                // here would let the user paste a header with
                // "(no events recorded)" into a support thread, which
                // is more confusing than helpful.
            } else {
                eventList
                actionRow
            }
        }
        .padding(.vertical, 4)
        .onDisappear {
            copyResetTask?.cancel()
            copyResetTask = nil
            didCopy = false
        }
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Newest first so the most relevant entry is at the top of
            // the card.
            ForEach(diagnostics.recentEvents.reversed()) { event in
                DiagnosticEventRow(event: event)
            }
        }
    }

    private var emptyState: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(ClaudeCodeTheme.success)
            VStack(alignment: .leading, spacing: 2) {
                Text("No issues recorded")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text("Critical errors and warnings will appear here.")
                    .font(.caption)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            Spacer()
        }
    }

    /// Footer row with the primary "Copy" affordance and the secondary
    /// "Clear" text button. The Copy button transitions to a transient
    /// "Copied" state with a check icon for two seconds after a tap so
    /// the user gets immediate confirmation without a separate toast or
    /// alert. Hidden entirely on platforms with no system clipboard
    /// (watchOS) so we never offer an action that does nothing. Only
    /// rendered when the buffer has at least one event; the empty
    /// state has no actions to surface.
    @ViewBuilder
    private var actionRow: some View {
        if Pasteboard.isAvailable {
            HStack(spacing: 8) {
                copyButton
                Spacer()
                clearButton
            }
            .padding(.top, 4)
        }
    }

    private var copyButton: some View {
        Button {
            performCopy()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .font(.caption.weight(.semibold))
                Text(didCopy ? "Copied" : "Copy diagnostics")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(didCopy ? ClaudeCodeTheme.success : ClaudeCodeTheme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                (didCopy ? ClaudeCodeTheme.success : ClaudeCodeTheme.accent)
                    .opacity(0.12),
                in: Capsule()
            )
            .overlay(
                Capsule()
                    .stroke(
                        (didCopy ? ClaudeCodeTheme.success : ClaudeCodeTheme.accent).opacity(0.4),
                        lineWidth: 0.5
                    )
            )
            .contentShape(Capsule())
            .animation(.easeInOut(duration: 0.18), value: didCopy)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(didCopy ? "Diagnostics copied to clipboard" : "Copy diagnostics to clipboard")
        .accessibilityAddTraits(.isButton)
    }

    private var clearButton: some View {
        Button("Clear") {
            diagnostics.clearAll()
        }
        .buttonStyle(.plain)
        .font(.caption.weight(.medium))
        .foregroundStyle(ClaudeCodeTheme.textSecondary)
    }

    private func performCopy() {
        let text = diagnostics.formatForClipboard()
        guard Pasteboard.copyString(text) else { return }

        // Bring the "Copied" affordance up immediately so the user sees
        // a definitive ack within the same frame, then schedule a
        // reset back to "Copy diagnostics" after two seconds. We
        // cancel any in-flight reset first so a double-click does not
        // race the reset early.
        copyResetTask?.cancel()
        didCopy = true
        copyResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            didCopy = false
        }
    }
}

// MARK: - DiagnosticEventRow

/// Single row inside `DiagnosticsRecentEventsList`. Compact two-line
/// layout: the user-facing message on top, the kind + relative
/// timestamp underneath. The optional `detail` (typically the
/// underlying error description) is hidden in a disclosure to keep
/// the row scannable while still being available for support.
private struct DiagnosticEventRow: View {
    let event: DiagnosticEvent

    @State private var isShowingDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: levelIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(levelColor)
                    .frame(width: 12)
                Text(event.message)
                    .font(.callout)
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(Self.relativeFormatter.localizedString(for: event.timestamp, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundStyle(ClaudeCodeTheme.textTertiary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                Text(event.kind)
                    .font(.caption2.monospaced())
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                if event.detail != nil {
                    Button {
                        isShowingDetail.toggle()
                    } label: {
                        Text(isShowingDetail ? "Hide details" : "Details")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(ClaudeCodeTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.leading, 18)
            if isShowingDetail, let detail = event.detail {
                detailText(detail)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func detailText(_ detail: String) -> some View {
        // `textSelection` is unavailable on watchOS, so the long-press
        // copy affordance only applies on iOS / macOS. Watch users get
        // the detail text but cannot select it; that is acceptable
        // because the watch surface is not a primary support channel.
        let base = Text(detail)
            .font(.caption2.monospaced())
            .foregroundStyle(ClaudeCodeTheme.textSecondary)
            .padding(.leading, 18)
            .padding(.top, 2)
            .fixedSize(horizontal: false, vertical: true)
        #if os(watchOS)
        base
        #else
        base.textSelection(.enabled)
        #endif
    }

    private var levelIcon: String {
        switch event.level {
        case .info: return "info.circle"
        case .warning: return "exclamationmark.circle.fill"
        case .critical: return "exclamationmark.triangle.fill"
        }
    }

    private var levelColor: Color {
        switch event.level {
        case .info: return ClaudeCodeTheme.textTertiary
        case .warning: return ClaudeCodeTheme.warning
        case .critical: return ClaudeCodeTheme.error
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()
}
