import Foundation

enum ServiceHealthState: String {
    case operational
    case degraded
    case majorOutage
    case stale
    case unavailable
}

@Observable
@MainActor
final class ServiceStatusMonitor {
    var state: ServiceHealthState = .operational
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
        endpoint: URL = URL(string: "https://status.anthropic.com/api/v2/status.json")!,
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
            state = status
            lastUpdatedAt = Date()
        } catch {
            if let lastUpdatedAt, Date().timeIntervalSince(lastUpdatedAt) > staleAfter {
                state = .stale
            } else if lastUpdatedAt != nil {
                state = .unavailable
            }
        }
    }

    private func fetchStatus() async throws -> ServiceHealthState {
        struct Payload: Decodable {
            struct ServiceStatus: Decodable {
                let indicator: String?
                let description: String?
            }

            let status: ServiceStatus?
        }

        let (data, response) = try await session.data(from: endpoint)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        return Self.map(
            indicator: payload.status?.indicator,
            description: payload.status?.description
        )
    }

    private static func map(indicator: String?, description: String?) -> ServiceHealthState {
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
}
