import SwiftUI

private enum IOSTab: Hashable {
    case dashboard
    case activity
    case settings
}

struct ContentView: View {
    let store: IOSAppStore
    @State private var selectedTab: IOSTab = .dashboard
    @State private var showsLaunchOverlay = true

    var body: some View {
        ZStack {
            ClaudeCodeTheme.background
                .ignoresSafeArea()

            TabView(selection: $selectedTab) {
                Tab("Dashboard", systemImage: "gauge.with.dots.needle.67percent", value: IOSTab.dashboard) {
                    DashboardTabView(store: store)
                }
                Tab("Activity", systemImage: "chart.xyaxis.line", value: IOSTab.activity) {
                    ActivityTabView(store: store)
                }
                Tab("Settings", systemImage: "gearshape", value: IOSTab.settings) {
                    SettingsTabView(store: store)
                }
            }

            if showsLaunchOverlay {
                launchOverlay
                    .transition(.opacity)
            }
        }
        .task {
            guard showsLaunchOverlay else { return }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.2)) {
                showsLaunchOverlay = false
            }
        }
        .preferredColorScheme(.dark)
        .tint(ClaudeCodeTheme.accent)
    }

    private var launchOverlay: some View {
        ZStack {
            ClaudeCodeTheme.background
                .ignoresSafeArea()
            VStack(spacing: 10) {
                ProgressView()
                    .tint(ClaudeCodeTheme.accent)
                Text("Loading dashboard...")
                    .font(.footnote)
                    .foregroundStyle(ClaudeCodeTheme.textSecondary)
            }
        }
    }
}
