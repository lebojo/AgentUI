import SwiftUI

struct GitChangeOutlineRow: View {
    @Binding var collapsed: Set<String>

    let row: GitChangeTreeRow
    let root: String
    let scope: GitChangeScope
    let source: any InspectorSource

    var body: some View {
        HStack(spacing: 0) {
            switch row.content {
            case .folder(let path, let name): GitChangeFolderRow(isCollapsed: $collapsed[contains: path], name: name, path: path)
            case .file(let change): GitChangeRow(change: change, root: root, scope: scope, source: source)
            }
        }
        .padding(.leading, CGFloat(row.depth) * (IconSize.xs + Spacing.xs))
    }
}
