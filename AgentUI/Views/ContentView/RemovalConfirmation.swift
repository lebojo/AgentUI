import SwiftUI

struct RemovalConfirmation: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkspaceStore.self) private var store
    @Environment(WorkspacePresentation.self) private var presentation

    @State private var prompt: Prompt?
    @State private var skipsConfirmation = false

    private var removal: Removal? { presentation.removal }
    private var branch: String? { prompt?.deletableBranch }

    var body: some View {
        ZStack {
            dialog(allowingSkip: true)
                .dialogSuppressionToggle("Don’t ask again", isSuppressed: $skipsConfirmation)
            dialog(allowingSkip: false)
        }
        .task(id: removal) {
            skipsConfirmation = false
            guard let removal else {
                prompt = nil
                return
            }
            let branch = await store.deletableBranch(for: removal)
            guard !Task.isCancelled else { return }
            prompt = Prompt(removal: removal, deletableBranch: branch)
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
            if !isPresented { presentation.removal = nil }
        }
    }

    private func confirm(_ branch: BranchRemoval) {
        guard let removal else { return }
        if skipsConfirmation { settings.confirmations.skip(removal) }
        store.remove(removal, branch: branch)
        presentation.removal = nil
    }

    private struct Prompt: Equatable {
        let removal: Removal
        let deletableBranch: String?
    }
}
