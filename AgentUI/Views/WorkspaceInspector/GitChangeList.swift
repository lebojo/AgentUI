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
                Label(scope.emptyTitle, systemImage: "checkmark.circle").foregroundStyle(Palette.textSecondary).font(Typography.body)
            }
            ForEach(outline.rows(collapsing: collapsed)) { row in
                Group {
                    switch row.content {
                    case .folder(let path, let name): GitChangeFolderRow(isCollapsed: $collapsed[contains: path], name: name, path: path)
                    case .file(let change): GitChangeRow(change: change, root: root, scope: scope, source: source)
                    }
                }
                .padding(.leading, CGFloat(row.depth) * (IconSize.xs + Spacing.xs))
            }
            if omitted > 0 {
                InspectorNotice(title: "Truncated List", message: String(localized: "\(omitted) more changes not shown on this device"), symbol: "ellipsis.circle")
            }
        }
    }
}
