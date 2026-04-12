import Foundation

// MARK: - TempoWidgetRoute

enum TempoWidgetRoute: String {
    case dashboard
    case stats

    static let scheme = "tempoforclaude"

    var url: URL {
        URL(string: "\(Self.scheme)://\(rawValue)")!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        if let host = url.host, let route = TempoWidgetRoute(rawValue: host.lowercased()) {
            self = route
            return
        }

        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard let route = TempoWidgetRoute(rawValue: path) else { return nil }
        self = route
    }
}
