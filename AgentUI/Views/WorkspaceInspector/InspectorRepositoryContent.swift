import SwiftUI

struct InspectorRepositoryContent: View {
    let model: InspectorStore
    let tab: InspectorTab
    let refresh: Int
    let context: TerminalContext
    let source: any InspectorSource

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if let local = model.local {
                    if tab == .git {
                        if let branch = local.branch { BranchBadge(branch: branch) }
                        WorkingTreeChanges(local: local, trees: model.changeTrees, context: context, source: source)
                        Divider()
                        RemoteSummary(model: model)
                        if model.lacksChangeRequest, let headSHA = local.headSHA {
                            Divider()
                            BranchComparisonSection(base: Bindable(model).comparisonBase, root: local.root, headSHA: headSHA, refresh: refresh, context: context, source: source)
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
