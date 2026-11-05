import SwiftUI

struct GitCommitComposer: View {
    @Environment(InspectorStore.self) private var model

    let root: String
    let hasStagedChanges: Bool
    let hasChanges: Bool
    let push: GitAction?
    let context: TerminalContext
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
                }
                Spacer(minLength: Spacing.xs)
                if model.pendingAction != nil { ProgressView().controlSize(.small) }
            }
            Button {
                source.runAgent(prompt: \.commit, name: String(localized: "Commits"), context: context)
            } label: {
                Label("Generate Commits with AI", systemImage: "sparkles")
            }
            .buttonStyle(.bordered)
            .disabled(!hasChanges || model.pendingAction != nil)
            .help("Open a terminal where the default agent commits the changes")
            if let error = model.actionError {
                InspectorNotice(title: "Git Action Failed", message: error)
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
