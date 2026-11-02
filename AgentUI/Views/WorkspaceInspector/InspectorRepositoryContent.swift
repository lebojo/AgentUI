import SwiftUI

struct InspectorRepositoryContent: View {
    let model: InspectorStore
    let tab: InspectorTab
    let refresh: Int
    let source: any InspectorSource

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if let local = model.local {
                    if tab == .git {
                        if let branch = local.branch { BranchBadge(branch: branch) }
                        GitChangeList(root: local.root, scope: .workingTree, changes: local.changes, omitted: local.omittedChanges)
                        Divider()
                        RemoteSummary(model: model)
                        if model.lacksChangeRequest, let headSHA = local.headSHA {
                            Divider()
                            BranchComparisonSection(base: Bindable(model).comparisonBase, root: local.root, headSHA: headSHA, refresh: refresh, source: source)
                        }
                    } else {
                        RemoteChecks(model: model, headSHA: local.headSHA)
                    }
                } else if let error = model.localError {
                    InspectorNotice(title: "Git Unavailable", message: error, symbol: "folder.badge.questionmark")
                } else {
                    Text("Reading repository…").foregroundStyle(Palette.textSecondary)
                }
            }.padding(Spacing.l).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
