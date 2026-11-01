import SwiftUI

struct UsageSignInButton: View {
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(UsageStore.self) private var usage
    @Environment(\.dismiss) private var dismiss

    let provider: UsageProvider

    var body: some View {
        if usage.pendingSignIns.contains(provider) {
            HStack(spacing: Spacing.s) {
                ProgressView().controlSize(.small)
                Text("Waiting for sign-in…").font(Typography.body).foregroundStyle(Palette.textSecondary)
            }
        } else {
            Button("Sign In…", action: signIn)
                .disabled(workspace.isReadOnly)
                .help("Opens an AgentUI terminal that runs “\(provider.signInCommand.joined(separator: " "))”")
        }
    }

    private func signIn() {
        do {
            try workspace.addTerminalInCurrentContext(name: String(localized: "\(provider.title) Sign-In"), command: provider.signInCommand)
            usage.watchSignIn(provider)
            dismiss()
        } catch {
            workspace.errorMessage = error.localizedDescription
        }
    }
}
