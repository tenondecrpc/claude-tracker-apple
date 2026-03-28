import SwiftUI

// MARK: - MacMenuView (top-level switcher)

struct MacMenuView: View {
    @Bindable var coordinator: MacAppCoordinator

    var body: some View {
        if coordinator.authState.isAuthenticated {
            AuthenticatedView(coordinator: coordinator)
        } else {
            SignInView(coordinator: coordinator)
        }
    }
}

// MARK: - SignInView

struct SignInView: View {
    @Bindable var coordinator: MacAppCoordinator

    @State private var pastedCode = ""
    @State private var isSubmitting = false
    @State private var signInError: String?

    var body: some View {
        if coordinator.authState.isAwaitingCode {
            codeEntryView
        } else {
            signInPromptView
        }
    }

    // MARK: - Sign-in Prompt

    private var signInPromptView: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("Claude Tracker")
                .font(.headline)
            Text("Sign in to sync Claude usage to your Apple Watch.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let error = signInError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button("Sign in with Claude") {
                signInError = nil
                coordinator.client.startOAuthFlow()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    // MARK: - Code Entry

    private var codeEntryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28))
                .foregroundStyle(.tint)
            Text("Paste Authorization Code")
                .font(.headline)
            Text("After authorizing in the browser, paste the code shown on screen.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            TextField("code#state", text: $pastedCode)
                .textFieldStyle(.roundedBorder)
            if let error = signInError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            HStack {
                Button("Cancel") {
                    pastedCode = ""
                    signInError = nil
                    coordinator.authState.isAwaitingCode = false
                }
                Spacer()
                Button("Submit") {
                    Task { await submitCode() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(pastedCode.isEmpty || isSubmitting)
            }
        }
        .padding()
    }

    // MARK: - Submit

    private func submitCode() async {
        isSubmitting = true
        signInError = nil
        defer { isSubmitting = false }
        do {
            try await coordinator.client.submitOAuthCode(pastedCode)
            pastedCode = ""
            coordinator.onAuthenticated()
        } catch {
            signInError = error.localizedDescription
        }
    }
}
