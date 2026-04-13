import SwiftUI
import AppKit

struct PreferencesWindowView: View {
    let coordinator: MacAppCoordinator
    var standalone: Bool = true
    @State private var hostingWindow: NSWindow?
    @State private var hasActivatedWindow = false
    @State private var use24HourTime: Bool

    init(coordinator: MacAppCoordinator, standalone: Bool = true) {
        self.coordinator = coordinator
        self.standalone = standalone
        _use24HourTime = State(initialValue: coordinator.settings.use24HourTime)
    }

    var body: some View {
        if standalone {
            ScrollView {
                preferencesContent
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(ClaudeCodeTheme.background)
            .background(PreferencesWindowAccessor(window: $hostingWindow))
            .onChange(of: hostingWindow, initial: true) { _, window in
                activateWindowIfNeeded(window)
            }
            .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, minHeight: 800)
        } else {
            preferencesContent
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var preferencesContent: some View {
        @Bindable var settings = coordinator.settings
        let needsClaudeAccess = coordinator.localDB.needsAccessGrant

        VStack(alignment: .leading, spacing: 16) {
            // Appearance card
            preferencesCard(title: "Appearance") {
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(ClaudeCodeTheme.accent)
                        .frame(width: 24, height: 24)
                    Text("Color Scheme")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(ClaudeCodeTheme.textPrimary)
                    Spacer(minLength: 12)
                    Picker("", selection: $settings.appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            }

            // General card
            preferencesCard(title: "General") {
                settingsRow(
                    icon: "power",
                    title: "Launch at Login",
                    subtitle: coordinator.launchAtLoginManager.helperMessage ?? "Start app when you log in",
                    toggle: Binding(
                        get: { coordinator.launchAtLoginManager.isEnabled },
                        set: { coordinator.setLaunchAtLoginEnabled($0) }
                    ),
                    isDisabled: !coordinator.launchAtLoginManager.isSupportedInstallLocation
                )
                Divider().overlay(ClaudeCodeTheme.progressTrack)
                settingsRow(
                    icon: "clock.arrow.2.circlepath",
                    title: "24-Hour Time",
                    subtitle: use24HourTime ? "Times shown as 14:30" : "Times shown as 02:30 PM",
                    toggle: Binding(
                        get: { use24HourTime },
                        set: { newValue in
                            use24HourTime = newValue
                            settings.use24HourTime = newValue
                        }
                    )
                )
            }

            preferencesCard(title: "Updates") {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "app.badge")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(ClaudeCodeTheme.accent)
                        .frame(width: 24, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Updates are managed by the App Store")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(ClaudeCodeTheme.textPrimary)
                        Text("Current version: \(coordinator.appUpdater.currentVersionDisplay)")
                            .font(.callout)
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    }

                    Spacer(minLength: 12)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)
            }

            preferencesCard(title: "Alerts") {
                settingsRow(
                    icon: "iphone",
                    title: "iPhone Notifications",
                    subtitle: needsClaudeAccess
                        ? "Grant access to your ~/.claude folder before enabling session notifications"
                        : "Show an experimental local iPhone alert when a Claude Code task finishes",
                    toggle: $settings.iPhoneAlertsEnabled,
                    isDisabled: needsClaudeAccess
                )
                Divider().overlay(ClaudeCodeTheme.progressTrack)
                settingsRow(
                    icon: "applewatch",
                    title: "Apple Watch Notifications",
                    subtitle: needsClaudeAccess
                        ? "Grant access to your ~/.claude folder before enabling watch relay alerts"
                        : "Relay experimental local completion alerts from iPhone to Apple Watch",
                    toggle: $settings.watchAlertsEnabled,
                    isDisabled: needsClaudeAccess
                )
                Divider().overlay(ClaudeCodeTheme.progressTrack)
                if needsClaudeAccess {
                    alertGrantAccessView
                        .padding(.top, 10)
                        .padding(.horizontal, 2)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Experimental local alerts only")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ClaudeCodeTheme.warning)
                        Text("No real push notifications: no backend, no device tokens, and no APNs infrastructure. Tempo only schedules local UNNotificationRequest alerts on-device.")
                            .font(.caption)
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        Text("These alerts can arrive late because delivery depends on iCloud sync and the iPhone-to-watch relay. Each device still needs notification permission from the OS. These preferences sync to the iPhone companion app via iCloud.")
                            .font(.caption)
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    }
                        .padding(.top, 10)
                        .padding(.horizontal, 2)
                }
            }

            // Menu Bar Display card - compact 2-column grid
            preferencesCard(title: "Menu Bar Display") {
                HStack(alignment: .top, spacing: 0) {
                    // 5-Hour column
                    VStack(alignment: .leading, spacing: 0) {
                        Text("5-Hour")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                            .padding(.bottom, 6)
                        menuBarCompactRow(
                            title: "Percentage",
                            example: "42%",
                            toggle: $settings.show5hPercentage
                        )
                        menuBarCompactRow(
                            title: "Reset Time",
                            example: use24HourTime ? "20:15" : "8:15p",
                            toggle: $settings.show5hResetTime
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()
                        .overlay(ClaudeCodeTheme.progressTrack)
                        .padding(.horizontal, 16)

                    // 7-Day column
                    VStack(alignment: .leading, spacing: 0) {
                        Text("7-Day")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(ClaudeCodeTheme.textSecondary)
                            .padding(.bottom, 6)
                        menuBarCompactRow(
                            title: "Percentage",
                            example: "18%",
                            toggle: $settings.show7dPercentage
                        )
                        menuBarCompactRow(
                            title: "Reset Day",
                            example: "sat",
                            toggle: $settings.show7dResetTime
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider().overlay(ClaudeCodeTheme.progressTrack).padding(.vertical, 10)

                // Extra usage - full-width compact row
                menuBarCompactRow(
                    title: "Extra Usage Credits",
                    example: "$3.20/$20",
                    toggle: $settings.showExtraUsageCredits
                )
            }

            // Data & Sync card
            preferencesCard(title: "Data & Sync") {
                settingsRow(
                    icon: "icloud",
                    title: "Sync History via iCloud",
                    subtitle: "Sync usage history across your Macs",
                    toggle: $settings.syncHistoryViaICloud
                )
                Divider().overlay(ClaudeCodeTheme.progressTrack)
                settingsRow(
                    icon: "dot.radiowaves.left.and.right",
                    title: "Service Status Monitoring",
                    subtitle: "Show Claude service status in the menu bar",
                    toggle: $settings.serviceStatusMonitoring
                )
            }

            // Account card
            preferencesCard(title: "Account") {
                if let email = coordinator.authState.accountEmail {
                    Text(email)
                        .font(.callout)
                        .foregroundStyle(ClaudeCodeTheme.textSecondary)
                        .padding(.vertical, 8)
                }
                Button("Sign Out") {
                    coordinator.client.signOut()
                }
                .buttonStyle(.plain)
                .foregroundStyle(ClaudeCodeTheme.error)
                .font(.subheadline.weight(.semibold))
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func preferencesCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(ClaudeCodeTheme.textSecondary)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .background(ClaudeCodeTheme.card)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func menuBarCompactRow(title: String, example: String, toggle: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text(example)
                    .font(.caption2)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: toggle)
                .labelsHidden()
                .toggleStyle(AccentSwitchToggleStyle())
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func settingsRow(
        icon: String,
        title: String,
        subtitle: String,
        toggle: Binding<Bool>,
        isDisabled: Bool = false
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(ClaudeCodeTheme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isDisabled ? ClaudeCodeTheme.textSecondary : ClaudeCodeTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: toggle)
                .labelsHidden()
                .toggleStyle(AccentSwitchToggleStyle())
                .disabled(isDisabled)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }

    private func activateWindowIfNeeded(_ window: NSWindow?) {
        guard standalone, !hasActivatedWindow, let window else { return }
        hasActivatedWindow = true

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    @ViewBuilder
    private var alertGrantAccessView: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .foregroundStyle(ClaudeCodeTheme.textSecondary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Claude folder access required")
                    .font(.caption.bold())
                    .foregroundStyle(ClaudeCodeTheme.textPrimary)
                Text("Grant read access to your ~/.claude folder to enable notification triggers.")
                    .font(.caption2)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }

            Spacer()

            Button("Grant Access") {
                coordinator.localDB.requestFolderAccess()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}

private struct PreferencesWindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            window = nsView.window
        }
    }
}

private struct AccentSwitchToggleStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(trackColor(isOn: configuration.isOn))
                    .overlay {
                        Capsule()
                            .stroke(borderColor, lineWidth: 1)
                    }

                Circle()
                    .fill(knobColor)
                    .shadow(color: .black.opacity(isEnabled ? 0.18 : 0.08), radius: 2, y: 1)
                    .padding(3)
            }
            .frame(width: 50, height: 30)
            .animation(.easeInOut(duration: 0.16), value: configuration.isOn)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(configuration.isOn ? "On" : "Off")
        .accessibilityValue(configuration.isOn ? "Enabled" : "Disabled")
    }

    private func trackColor(isOn: Bool) -> Color {
        if isOn {
            return isEnabled ? ClaudeCodeTheme.accent : ClaudeCodeTheme.textTertiary
        }
        return isEnabled ? ClaudeCodeTheme.progressTrack : ClaudeCodeTheme.progressTrack.opacity(0.75)
    }

    private var borderColor: Color {
        isEnabled ? ClaudeCodeTheme.border.opacity(0.65) : ClaudeCodeTheme.border.opacity(0.4)
    }

    private var knobColor: Color {
        isEnabled ? ClaudeCodeTheme.textPrimary : ClaudeCodeTheme.textSecondary
    }
}
