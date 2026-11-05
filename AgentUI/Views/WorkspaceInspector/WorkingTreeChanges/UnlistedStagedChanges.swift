import SwiftUI

struct UnlistedStagedChanges: View {
    let root: String
    let source: any InspectorSource

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text("Staged Changes").font(Typography.sectionTitle)
                Spacer(minLength: Spacing.xs)
                if source.canWriteRepository {
                    GitActionButton(action: .unstageAll, root: root, source: source)
                        .labelStyle(.titleOnly).buttonStyle(.borderless).font(Typography.caption)
                }
            }
            .padding(.bottom, Spacing.xs)
            Text("Staged changes aren’t listed.")
                .foregroundStyle(Palette.textSecondary).font(Typography.body)
        }
    }
}
