import SwiftUI

struct GitChangeList: View {
    @State private var collapsed: Set<String> = []

    let root: String
    let scope: GitChangeScope
    let outline: GitChangeOutline
    let omitted: Int
    let source: any InspectorSource

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(scope.title(count: outline.count + omitted)).font(Typography.sectionTitle)
                Spacer(minLength: Spacing.xs)
                if source.canWriteRepository, !outline.isEmpty, let action = scope.bulkAction {
                    GitActionButton(action: action, root: root, source: source)
                        .labelStyle(.titleOnly).buttonStyle(.borderless).font(Typography.caption)
                }
            }
            .padding(.bottom, Spacing.xs)
            if outline.isEmpty {
                Label { Text(scope.emptyTitle) } icon: { Image(systemName: "checkmark.circle") }
                    .foregroundStyle(Palette.textSecondary).font(Typography.body)
            }
            ForEach(outline.rows(collapsing: collapsed)) { row in
                GitChangeOutlineRow(collapsed: $collapsed, row: row, root: root, scope: scope, source: source)
            }
            if omitted > 0 {
                InspectorNotice(title: "Truncated List", message: "\(omitted) more changes not shown on this device", symbol: "ellipsis.circle")
            }
        }
    }
}
