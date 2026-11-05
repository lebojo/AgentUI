import SwiftUI

struct RemovalConfirmation: View {
    @Environment(SettingsStore.self) private var settings

    @State private var prompt: Prompt?
    @State private var skipsConfirmation = false

    @Binding var removal: Removal?

    let store: WorkspaceStore

    private var branch: String? { prompt?.deletableBranch }

    var body: some View {
        ZStack {
            dialog(allowingSkip: true)
                .dialogSuppressionToggle("Don’t ask again", isSuppressed: $skipsConfirmation)
            dialog(allowingSkip: false)
        }
        .onChange(of: removal) {
            skipsConfirmation = false
            prompt = removal.map { Prompt(removal: $0, deletableBranch: store.deletableBranch(for: $0)) }
        }
    }

    private func dialog(allowingSkip: Bool) -> some View {
        Color.clear.confirmationDialog(removal?.title ?? "", isPresented: isPresented(allowingSkip: allowingSkip), titleVisibility: .visible) {
            Button(removal?.confirmation(deletableBranch: branch) ?? "", role: .destructive) { confirm(.keep) }
            if branch != nil {
                Button("Delete Worktree and Branch", role: .destructive) { confirm(.merged) }
            }
        } message: { Text(removal?.message(deletableBranch: branch) ?? "") }
    }

    private func isPresented(allowingSkip: Bool) -> Binding<Bool> {
        Binding {
            guard let removal, prompt?.removal == removal else { return false }
            return removal.allowsSkippingConfirmation == allowingSkip
        } set: { isPresented in
            if !isPresented { removal = nil }
        }
    }

    private func confirm(_ branch: BranchRemoval) {
        guard let removal else { return }
        if skipsConfirmation { settings.confirmations.skip(removal) }
        store.remove(removal, branch: branch)
        self.removal = nil
    }

    private struct Prompt: Equatable {
        let removal: Removal
        let deletableBranch: String?
    }
}
