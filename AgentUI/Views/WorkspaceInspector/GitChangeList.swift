import SwiftUI

struct GitChangeList: View {
    let root: String
    let scope: GitChangeScope
    let changes: [GitChange]
    let omitted: Int

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Spacing.m) {
            Text("Changes · \(changes.count + omitted)").font(Typography.sectionTitle)
            if changes.isEmpty {
                Label(scope.emptyTitle, systemImage: "checkmark.circle").foregroundStyle(Palette.textSecondary).font(Typography.body)
            }
            ForEach(changes) { change in
                GitChangeRow(change: change, root: root, scope: scope)
            }
            if omitted > 0 {
                InspectorNotice(title: "Truncated List", message: String(localized: "\(omitted) more changes not shown on this device"), symbol: "ellipsis.circle")
            }
        }
    }
}
