import SwiftUI

struct PreferencesWindowView: View {
    let coordinator: MacAppCoordinator
    var standalone: Bool = true
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
            .background(TempoTheme.background)
            .preferredColorScheme(.dark)
            .frame(minWidth: 420, idealWidth: 460, maxWidth: 520, minHeight: 800)
        } else {
            preferencesContent
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var preferencesContent: some View {
        @Bindable var settings = coordinator.settings

        VStack(alignment: .leading, spacing: 16) {
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
                Divider().overlay(TempoTheme.progressTrack)
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
                settingsRow(
                    icon: "arrow.trianglehead.2.clockwise.rotate.90",
                    title: "Automatic Update Checks",
                    subtitle: "Check GitHub releases on launch (max every 12 hours)",
                    toggle: $settings.autoCheckForUpdates
                )

                Divider().overlay(TempoTheme.progressTrack)

                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Current Version")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(TempoTheme.textPrimary)
                        Text(coordinator.appUpdater.currentVersionDisplay)
                            .font(.caption)
                            .foregroundStyle(TempoTheme.textSecondary)
                    }

                    Spacer(minLength: 12)

                    if coordinator.appUpdater.isChecking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(TempoTheme.textSecondary)
                    } else if coordinator.appUpdater.availableVersion != nil {
                        Button("Download Update") {
                            coordinator.appUpdater.openLatestRelease()
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TempoTheme.accent)
                    } else {
                        Button("Check Now") {
                            Task {
                                await coordinator.appUpdater.checkForUpdates(userInitiated: true)
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TempoTheme.accent)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 2)

                if let statusMessage = coordinator.appUpdater.statusMessage {
                    Divider().overlay(TempoTheme.progressTrack)

                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(TempoTheme.textSecondary)
                        .padding(.top, 10)
                        .padding(.horizontal, 2)
                }
            }

            // Menu Bar Display card — compact 2-column grid
            preferencesCard(title: "Menu Bar Display") {
                HStack(alignment: .top, spacing: 0) {
                    // 5-Hour column
                    VStack(alignment: .leading, spacing: 0) {
                        Text("5-Hour")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TempoTheme.textSecondary)
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
                        .overlay(TempoTheme.progressTrack)
                        .padding(.horizontal, 16)

                    // 7-Day column
                    VStack(alignment: .leading, spacing: 0) {
                        Text("7-Day")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(TempoTheme.textSecondary)
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

                Divider().overlay(TempoTheme.progressTrack).padding(.vertical, 10)

                // Extra usage — full-width compact row
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
                Divider().overlay(TempoTheme.progressTrack)
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
                        .foregroundStyle(TempoTheme.textSecondary)
                        .padding(.vertical, 8)
                }
                Button("Sign Out") {
                    coordinator.client.signOut()
                }
                .buttonStyle(.plain)
                .foregroundStyle(TempoTheme.critical)
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
                .foregroundStyle(TempoTheme.textSecondary)
                .padding(.bottom, 8)

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(16)
            .background(TempoTheme.card)
            .clipShape(.rect(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private func menuBarCompactRow(title: String, example: String, toggle: Binding<Bool>) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(TempoTheme.textPrimary)
                Text(example)
                    .font(.caption2)
                    .foregroundStyle(TempoTheme.textSecondary)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: toggle)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(TempoTheme.accent)
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
                .foregroundStyle(TempoTheme.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isDisabled ? TempoTheme.textSecondary : TempoTheme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(TempoTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: toggle)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(TempoTheme.accent)
                .disabled(isDisabled)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 2)
    }
}
