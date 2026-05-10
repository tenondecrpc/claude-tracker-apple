import Foundation

// MARK: - TempoWidgetRoute

/// Deep-link target opened by a widget tap.
///
/// The route carries two independent pieces of information:
///
/// - `kind`: which surface to open (`.dashboard` on iOS, `.stats` on macOS
///   for the detail window). Encoded as the URL host so SwiftUI's
///   `handlesExternalEvents(matching:)` can match on the host string.
/// - `accountId`: optional canonical accountId (lowercased email or
///   synthetic id) to activate before rendering the surface. Encoded as
///   a URL query item so the existing `handlesExternalEvents` matching
///   set does not have to change. Absent or empty means "use whatever
///   account is currently active on the target device" (the
///   backwards-compatible default).
///
/// Convention for URLs produced by this type:
///
///     tempoforclaude://dashboard                          // follow active account
///     tempoforclaude://dashboard?accountId=alice%40x.com  // switch to alice then open dashboard
///
/// Multi-account support (see the `multi-account-support` OpenSpec
/// change, task 8.4) requires widgets to embed the rendered snapshot's
/// accountId on the tap URL so the app lands on the same account the
/// user saw on the widget face.
struct TempoWidgetRoute: Equatable, Hashable {
    enum Kind: String, CaseIterable, Hashable {
        case dashboard
        case stats
    }

    let kind: Kind
    /// Canonical accountId (lowercased email or synthetic) to activate
    /// before rendering the surface. `nil` means "follow the current
    /// active account" and is the only shape produced by routes that
    /// predate the multi-account change.
    let accountId: String?

    static let scheme = "tempoforclaude"

    /// Name of the URL query item used to carry the accountId.
    static let accountIdQueryKey = "accountId"

    // Convenience constants so call sites that don't care about an
    // account (widget smoke test, `handlesExternalEvents` match list)
    // can keep the concise `.dashboard` / `.stats` usage. Both omit
    // `accountId`, which means the default "follow active account"
    // behaviour applies when they are tapped.
    static let dashboard = TempoWidgetRoute(kind: .dashboard, accountId: nil)
    static let stats = TempoWidgetRoute(kind: .stats, accountId: nil)

    init(kind: Kind, accountId: String? = nil) {
        self.kind = kind
        // Treat empty strings as "no accountId" so callers can safely
        // pass an optional accountId without having to null-coalesce
        // empty strings themselves.
        if let id = accountId, !id.isEmpty {
            self.accountId = id
        } else {
            self.accountId = nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = kind.rawValue
        if let accountId {
            components.queryItems = [
                URLQueryItem(name: Self.accountIdQueryKey, value: accountId),
            ]
        }
        // `components.url` is only non-nil when scheme/host are set, which
        // is always the case here. Force-unwrap is safe; if it ever
        // becomes nil we want the crash so the bug surfaces.
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        let resolvedKind: Kind? = {
            if let host = url.host, let kind = Kind(rawValue: host.lowercased()) {
                return kind
            }
            let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
            return Kind(rawValue: path)
        }()
        guard let kind = resolvedKind else { return nil }
        let accountId = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == Self.accountIdQueryKey })?
            .value
        self.init(kind: kind, accountId: accountId)
    }
}
