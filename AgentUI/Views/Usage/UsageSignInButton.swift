import SwiftUI

struct UsageSignInButton: View {
    @Environment(WorkspaceStore.self) private var workspace
    @Environment(UsageStore.self) private var usage
    @Environment(\.dismiss) private var dismiss
    let provider: UsageProvider

    var body: some View {
        if usage.pendingSignIns.contains(provider) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("En attente de la connexion…").font(.callout).foregroundStyle(.secondary)
            }
        } else {
            Button("Se connecter…", action: signIn)
                .disabled(workspace.isReadOnly)
                .help("Ouvre un terminal AgentUI qui lance « \(provider.signInCommand.joined(separator: " ")) »")
        }
    }

    private func signIn() {
        do {
            try workspace.addTerminalInCurrentContext(name: "Connexion \(provider.title)", command: provider.signInCommand)
            usage.watchSignIn(provider)
            dismiss()
        } catch {
            workspace.errorMessage = error.localizedDescription
        }
    }
}
