import SwiftUI

struct GitChangeSectionHeader: View {
    let title: LocalizedStringResource
    let action: GitAction?
    let root: String
    let source: any InspectorSource

    var body: some View {
        HStack {
            Text(title).font(Typography.sectionTitle)
            Spacer(minLength: Spacing.xs)
            if source.canWriteRepository, let action {
                GitActionButton(action: action, root: root, source: source)
                    .labelStyle(.titleOnly).buttonStyle(.borderless).font(Typography.caption)
            }
        }
        .padding(.bottom, Spacing.xs)
    }
}
