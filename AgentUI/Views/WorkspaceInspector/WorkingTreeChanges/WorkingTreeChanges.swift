import SwiftUI

struct WorkingTreeChanges: View {
    let root: String
    let trees: GitChangeTrees
    let hasChanges: Bool
    let hasStagedChanges: Bool
    let omission: WorkingTreeOmission
    let push: GitAction?
    let republish: GitAction?
    let upstreamIsGone: Bool
    let source: any InspectorSource

    var body: some View {
        if source.canWriteRepository {
            GitCommitComposer(root: root, hasStagedChanges: hasStagedChanges, hasChanges: hasChanges,
                              push: push, republish: republish, upstreamIsGone: upstreamIsGone, source: source)
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
