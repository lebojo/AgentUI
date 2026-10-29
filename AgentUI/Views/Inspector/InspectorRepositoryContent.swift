import SwiftUI

struct InspectorRepositoryContent: View {
    let model: InspectorStore
    let tab: InspectorTab

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.xl) {
                if let local = model.local {
                    if tab == .git {
                        GitChangeList(root: local.root, branch: local.branch, changes: local.changes)
                        Divider()
                        GitHubSummary(model: model)
                    } else {
                        GitHubChecks(model: model, headSHA: local.headSHA)
                    }
                } else if let error = model.localError {
                    InspectorNotice(title: "Git indisponible", message: error, symbol: "folder.badge.questionmark")
                } else {
                    Text("Lecture du dépôt…").foregroundStyle(Palette.textSecondary)
                }
            }.padding(Spacing.l).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
