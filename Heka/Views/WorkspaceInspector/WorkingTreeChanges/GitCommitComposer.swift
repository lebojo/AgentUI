import SwiftUI

struct GitCommitComposer: View {
    @Environment(InspectorStore.self) private var model
    @Environment(\.inspectedWorktree) private var worktree

    let root: String
    let hasStagedChanges: Bool
    let hasChanges: Bool
    let push: GitAction?
    let republish: GitAction?
    let upstreamIsGone: Bool
    let source: any InspectorSource

    private var commit: GitAction? {
        hasStagedChanges ? draft : nil
    }

    private var draft: GitAction? {
        GitAction.commit(title: model.commitTitle, description: model.commitMessage)
    }

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Spacing.s) {
            TextField("Commit Title", text: $model.commitTitle).onSubmit(commitChanges)
            TextField("Description", text: $model.commitMessage, axis: .vertical).lineLimit(2...6)
            HStack(spacing: Spacing.s) {
                Button("Commit", action: commitChanges)
                    .buttonStyle(.borderedProminent)
                    .disabled(commit == nil || model.pendingAction != nil)
                if let push {
                    GitActionButton(action: push, root: root, source: source)
                        .buttonStyle(.bordered)
                        .disabled(model.pendingAction != nil)
                } else if upstreamIsGone {
                    Text("The remote branch was deleted")
                        .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    if let republish {
                        GitActionButton(action: republish, root: root, source: source)
                            .buttonStyle(.borderless)
                            .disabled(model.pendingAction != nil)
                    }
                }
                Spacer(minLength: Spacing.xs)
                if model.pendingAction != nil {
                    ProgressView().controlSize(.small)
                    Button("Cancel", action: model.cancelActions)
                        .buttonStyle(.borderless)
                        .help("Stop the running Git command and drop the waiting ones")
                }
            }
            Button {
                if let worktree { source.runAgent(.commit, name: String(localized: "Commits"), in: worktree) }
            } label: {
                Label("Generate Commits with AI", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .disabled(worktree == nil || !hasChanges || model.pendingAction != nil)
            .help("Open a terminal where the default agent commits the changes")
            if let failure = model.actionFailure {
                GitActionFailureNotice(message: failure.message)
            }
        }
        .controlSize(.small)
        .font(Typography.body)
    }

    private func commitChanges() {
        guard let commit, model.pendingAction == nil else { return }
        Task {
            guard await model.perform(commit, at: root, with: source), draft == commit else { return }
            model.commitTitle = ""
            model.commitMessage = ""
        }
    }
}
