import SwiftUI
import Foundation

struct CompletionView: View {
    let session: SessionInfo

    var body: some View {
        VStack(spacing: 8) {
            Text("Session Done")
                .font(.headline)

            Text("\(session.inputTokens + session.outputTokens) tokens")
                .font(.title3)
                .fontWeight(.semibold)

            Text(session.costUSD, format: .currency(code: "USD"))
                .font(.caption)
                .foregroundStyle(.secondary)

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
