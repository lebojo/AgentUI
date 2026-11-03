import SwiftUI

struct UnlistedStagedChanges: View {
    let root: String
    let source: any InspectorSource

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            GitChangeSectionHeader(title: "Staged Changes", action: GitChangeScope.staged.bulkAction, root: root, source: source)
            Text("Staged changes aren’t listed.")
                .foregroundStyle(Palette.textSecondary).font(Typography.body)
        }
    }
}
