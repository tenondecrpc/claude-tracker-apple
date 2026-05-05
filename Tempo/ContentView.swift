import SwiftUI

private enum IOSTab: Hashable {
    case dashboard
    case activity
    case settings
}

struct ContentView: View {
    let store: IOSAppStore
    let widgetRoute: TempoWidgetRoute?
    @State private var selectedTab: IOSTab = .dashboard

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
        }
        .tint(ClaudeCodeTheme.accent)
        .onChange(of: widgetRoute, initial: true) { _, route in
            guard let route else { return }
            switch route {
            case .dashboard, .stats:
                selectedTab = .dashboard
            }
        }
    }
}
