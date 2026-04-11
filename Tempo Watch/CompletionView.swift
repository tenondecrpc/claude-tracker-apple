import Foundation
import SwiftUI

struct CompletionView: View {
    let session: SessionInfo

    var body: some View {
        let presentation = session.notificationPresentation()

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

            Text("Tap to dismiss")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
        }
        .padding()
    }
}

#Preview {
    CompletionView(session: SessionInfo(
        sessionId: "preview-1",
        inputTokens: 4200,
        outputTokens: 1800,
        costUSD: 0.0,
        durationSeconds: 142,
        timestamp: Date()
    ))
}
