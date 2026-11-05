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
        .alert(store.unmergedRemoval?.reason ?? "", isPresented: Bindable(store).unmergedRemoval.isPresent, presenting: store.unmergedRemoval) { unmerged in
            Button("Delete Worktree Only", role: .destructive) { store.remove(unmerged.removal) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Nothing was removed. You can delete the worktree and keep the branch and its commits in the repository.")
        }
        .task(id: removal) {
            skipsConfirmation = false
            guard let removal else {
                prompt = nil
                return
            }
            await present(removal)
        }
    }

    private func present(_ removal: Removal) async {
        let store = store
        await withTaskGroup(of: BranchLookup.self) { group in
            group.addTask { .found(await store.deletableBranch(for: removal)) }
            group.addTask {
                try? await Task.sleep(for: Removal.branchLookupDeadline)
                return .timedOut
            }
            let first = await group.next()
            group.cancelAll()
            guard !Task.isCancelled, let first else { return }
            prompt = Prompt(removal: removal, deletableBranch: first.branch)
        }
    }

    private func dialog(allowingSkip: Bool) -> some View {
        Color.clear.confirmationDialog(removal?.title ?? "", isPresented: isPresented(allowingSkip: allowingSkip), titleVisibility: .visible) {
            Button(role: .destructive) { confirm(.keep) } label: { Text(removal?.confirmation(deletableBranch: branch) ?? "") }
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

    private enum BranchLookup: Sendable {
        case found(String?), timedOut

        var branch: String? {
            if case .found(let branch) = self { branch } else { nil }
        }
    }
}
