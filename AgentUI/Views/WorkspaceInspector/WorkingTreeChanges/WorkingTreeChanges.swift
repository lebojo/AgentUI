import SwiftUI

struct WorkingTreeChanges: View {
    let local: LocalGitSnapshot
    let trees: GitChangeTrees
    let context: TerminalContext
    let source: any InspectorSource

    var body: some View {
        Group {
            if source.canWriteRepository {
                GitCommitComposer(root: local.root, hasStagedChanges: !trees.staged.isEmpty, hasChanges: !local.changes.isEmpty,
                                  push: local.push, context: context, source: source)
            }
            if !trees.staged.isEmpty {
                GitChangeList(root: local.root, scope: .staged, tree: trees.staged, omitted: 0, source: source)
            }
            GitChangeList(root: local.root, scope: .unstaged, tree: trees.unstaged, omitted: local.omittedChanges, source: source)
        }
    }
}
