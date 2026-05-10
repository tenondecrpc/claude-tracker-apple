import Foundation
import SwiftUI

struct CompletionView: View {
    /// Pulled from the environment so the sheet, which is presented from
    /// `RootView` via `.sheet(item: $bindableStore.pendingCompletion)` with
    /// only the `SessionInfo` bound, can still surface the account label
    /// without threading an additional parameter through the sheet closure.
    /// Matches task 7.4 in the multi-account-support change: the completion
    /// card must identify which account's session finished.
    @Environment(TokenStore.self) private var store

    let session: SessionInfo

    var body: some View {
        let presentation = session.notificationPresentation()
        let accountLine = displayAccountLine()

        VStack(spacing: 8) {
            Text(presentation.title)
                .font(.headline)
                .multilineTextAlignment(.center)

            Text(presentation.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text(presentation.body)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if !accountLine.isEmpty {
                Text(accountLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                    .accessibilityLabel("Account: \(accountLine)")
            }

            Text("Tap to dismiss")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding()
    }

    /// Builds the small footer line shown under the completion card so the
    /// user can tell which account just wrapped up a session.
    ///
    /// Preference order per task 7.4:
    /// 1. `AccountIdentifier.unassignedAccountId` sessions are CLI-only and
    ///    have no user-visible label to anchor on, so we surface the neutral
    ///    "CLI-only session" copy.
    /// 2. Otherwise, prefer the iPhone-provided `accountLabel` (typically the
    ///    email address or a user-set display name), which is the same
    ///    string rendered in the dashboard header in task 7.3.
    /// 3. Fall back to the canonical `accountId` on the session when the
    ///    store has no label yet (for example, a completion payload arrived
    ///    before any `UsageState` relayed the label).
    private func displayAccountLine() -> String {
        if session.accountId == AccountIdentifier.unassignedAccountId {
            return "CLI-only session"
        }
        if !store.accountLabel.isEmpty {
            return "for \(store.accountLabel)"
        }
        if !session.accountId.isEmpty {
            return "for \(session.accountId)"
        }
        return ""
    }
}

#Preview {
    CompletionPreviewHost()
}

/// Host view used only by the `#Preview` above so we can seed a
/// `TokenStore` with a realistic `accountLabel` before binding it into the
/// SwiftUI environment. The store must be constructed on the main actor
/// because `TokenStore` is `@MainActor` isolated; `@State` inside a
/// `@MainActor` view gives us that guarantee while keeping the preview
/// self-contained.
@MainActor
private struct CompletionPreviewHost: View {
    @State private var store: TokenStore = {
        let store = TokenStore()
        store.applyActiveAccount(id: "alice@example.com", label: "alice@example.com")
        return store
    }()

    var body: some View {
        CompletionView(session: SessionInfo(
            sessionId: "preview-1",
            inputTokens: 4200,
            outputTokens: 1800,
            costUSD: 0.0,
            durationSeconds: 142,
            timestamp: Date(),
            accountId: "alice@example.com"
        ))
        .environment(store)
    }
}
