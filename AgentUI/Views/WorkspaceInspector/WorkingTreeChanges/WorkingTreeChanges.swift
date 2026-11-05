import SwiftUI

struct WorkingTreeChanges: View {
    let root: String
    let trees: GitChangeTrees
    let hasChanges: Bool
    let omission: WorkingTreeOmission
    let push: GitAction?
    let upstreamIsGone: Bool
    let context: TerminalContext
    let source: any InspectorSource

    var body: some View {
        if source.canWriteRepository {
            GitCommitComposer(root: root, hasStagedChanges: !trees.staged.isEmpty, hasChanges: hasChanges,
                              push: push, upstreamIsGone: upstreamIsGone, context: context, source: source)
        }
        if !trees.staged.isEmpty {
            GitChangeList(root: root, scope: .staged, outline: trees.staged, omitted: 0, source: source)
        }
        GitChangeList(root: root, scope: .unstaged, outline: trees.unstaged, omitted: 0, source: source)
        if omission.count > 0 {
            InspectorNotice(title: "Truncated List", message: omission.message(includingBulkActions: source.canWriteRepository), symbol: "ellipsis.circle")
        }
    }
}
