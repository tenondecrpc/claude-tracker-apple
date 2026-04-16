import Foundation

enum ServiceHealthState: String {
    case operational
    case degraded
    case majorOutage
    case stale
    case unavailable
}

private extension ServiceHealthState {
    var severity: Int {
        switch self {
        case .operational: return 0
        case .degraded, .stale: return 1
        case .majorOutage: return 2
        case .unavailable: return -1
        }
    }
}

@Observable
@MainActor
final class ServiceStatusMonitor {
    var state: ServiceHealthState = .operational
    var affectedServiceName: String?
    var lastUpdatedAt: Date?
    var lastAttemptAt: Date?
    var isRunning = false

    private let session: URLSession
    private let endpoint: URL
    private let pollInterval: TimeInterval
    private let staleAfter: TimeInterval
    private var timer: Timer?

    init(
        session: URLSession = .shared,
        endpoint: URL = URL(string: "https://status.claude.com/api/v2/summary.json")!,
        pollInterval: TimeInterval = 5 * 60,
        staleAfter: TimeInterval = 20 * 60
    ) {
        self.session = session
        self.endpoint = endpoint
        self.pollInterval = pollInterval
        self.staleAfter = staleAfter
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        Task { [weak self] in
            await self?.pollOnce()
        }
        schedule()
    }

    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }

    private func schedule() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning else { return }
                await self.pollOnce()
            }
        }
    }

    private func pollOnce() async {
        lastAttemptAt = Date()
        do {
            let status = try await fetchStatus()
            state = status.state
            affectedServiceName = status.affectedServiceName
            lastUpdatedAt = Date()
        } catch {
            affectedServiceName = nil
            if let lastUpdatedAt, Date().timeIntervalSince(lastUpdatedAt) > staleAfter {
                state = .stale
            } else if lastUpdatedAt != nil {
                state = .unavailable
            }
        }
    }

    private struct ServiceStatusResult {
        let state: ServiceHealthState
        let affectedServiceName: String?
    }

    private struct Payload: Decodable {
        struct ServiceStatus: Decodable {
            let indicator: String?
            let description: String?
        }

        struct Component: Decodable {
            let group: Bool?
            let name: String?
            let position: Int?
            let showcase: Bool?
            let status: String?
        }

        struct Incident: Decodable {
            let impact: String?
            let name: String?
        }

        let status: ServiceStatus?
        let components: [Component]?
        let incidents: [Incident]?
    }

    private struct ComponentIssue {
        let name: String
        let position: Int
        let showcase: Bool
        let state: ServiceHealthState
    }

    private func fetchStatus() async throws -> ServiceStatusResult {

        let (data, response) = try await session.data(from: endpoint)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return Self.map(payload)
    }

    private static func map(_ payload: Payload) -> ServiceStatusResult {
        let componentIssues = (payload.components ?? [])
            .compactMap(componentIssue(from:))
            .sorted(by: compareComponentIssues)
        let incidentState = maxSeverity((payload.incidents ?? []).map {
            mapIncidentImpact($0.impact)
        })
        let rollupState = mapRollup(
            indicator: payload.status?.indicator,
            description: payload.status?.description
        )
        let overallState = maxSeverity(
            [rollupState, incidentState, componentIssues.first?.state].compactMap { $0 }
        ) ?? .unavailable

        if overallState == .operational {
            return ServiceStatusResult(state: .operational, affectedServiceName: nil)
        }

        return ServiceStatusResult(
            state: overallState,
            affectedServiceName: summarizeComponentNames(componentIssues)
                ?? firstIncidentName(payload.incidents ?? [])
        )
    }

    private static func mapRollup(indicator: String?, description: String?) -> ServiceHealthState {
        let merged = [indicator, description]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        if merged.contains("none") || merged.contains("operational") {
            return .operational
        }
        if merged.contains("major") || merged.contains("critical") || merged.contains("outage") {
            return .majorOutage
        }
        if merged.contains("minor") || merged.contains("degraded") || merged.contains("partial") {
            return .degraded
        }
        return .unavailable
    }

    private static func componentIssue(from component: Payload.Component) -> ComponentIssue? {
        guard component.group != true else { return nil }
        guard let name = normalized(component.name) else { return nil }

        let state = mapComponentStatus(component.status)
        guard state == .degraded || state == .majorOutage else { return nil }

        return ComponentIssue(
            name: name,
            position: component.position ?? .max,
            showcase: component.showcase ?? false,
            state: state
        )
    }

    private static func compareComponentIssues(_ lhs: ComponentIssue, _ rhs: ComponentIssue) -> Bool {
        if lhs.state.severity != rhs.state.severity {
            return lhs.state.severity > rhs.state.severity
        }
        if lhs.showcase != rhs.showcase {
            return lhs.showcase && !rhs.showcase
        }
        if lhs.position != rhs.position {
            return lhs.position < rhs.position
        }
        return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
    }

    private static func mapComponentStatus(_ status: String?) -> ServiceHealthState {
        let normalizedStatus = status?.lowercased() ?? ""

        if normalizedStatus.contains("major_outage") || normalizedStatus.contains("major outage") {
            return .majorOutage
        }
        if normalizedStatus.contains("partial_outage")
            || normalizedStatus.contains("partial outage")
            || normalizedStatus.contains("degraded_performance")
            || normalizedStatus.contains("degraded performance")
            || normalizedStatus.contains("maintenance") {
            return .degraded
        }
        if normalizedStatus.contains("operational") {
            return .operational
        }
        return .unavailable
    }

    private static func mapIncidentImpact(_ impact: String?) -> ServiceHealthState {
        let normalizedImpact = impact?.lowercased() ?? ""

        if normalizedImpact.contains("critical") || normalizedImpact.contains("major") {
            return .majorOutage
        }
        if normalizedImpact.contains("minor") {
            return .degraded
        }
        return .unavailable
    }

    private static func maxSeverity(_ states: [ServiceHealthState]) -> ServiceHealthState? {
        states.max { lhs, rhs in
            lhs.severity < rhs.severity
        }
    }

    private static func summarizeComponentNames(_ componentIssues: [ComponentIssue]) -> String? {
        var seenNames = Set<String>()
        var orderedNames: [String] = []

        for componentIssue in componentIssues {
            guard seenNames.insert(componentIssue.name).inserted else { continue }
            orderedNames.append(componentIssue.name)
        }

        guard let firstName = orderedNames.first else { return nil }
        let additionalCount = orderedNames.count - 1

        if additionalCount == 0 {
            return firstName
        }

        return "\(firstName) + \(additionalCount) more"
    }

    private static func firstIncidentName(_ incidents: [Payload.Incident]) -> String? {
        incidents.compactMap { normalized($0.name) }.first
    }

    private static func normalized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }
        return trimmed.isEmpty ? nil : trimmed
    }
}
