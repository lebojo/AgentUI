import SwiftUI

struct WorkingTreeChanges: View {
    let root: String
    let trees: GitChangeTrees
    let hasChanges: Bool
    let omitted: Int
    let push: GitAction?
    let context: TerminalContext
    let source: any InspectorSource

    var body: some View {
        if source.canWriteRepository {
            GitCommitComposer(root: root, hasStagedChanges: !trees.staged.isEmpty, hasChanges: hasChanges,
                              push: push, context: context, source: source)
        }
        if !trees.staged.isEmpty {
            GitChangeList(root: root, scope: .staged, outline: trees.staged, omitted: 0, source: source)
        }
        GitChangeList(root: root, scope: .unstaged, outline: trees.unstaged, omitted: omitted, source: source)
    }
}
