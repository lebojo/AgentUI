import SwiftUI

struct GitChangeList: View {
    let root: String
    let branch: GitBranch?
    let changes: [GitChange]
    let omitted: Int

    var body: some View {
        if let branch { BranchBadge(branch: branch) }
        LazyVStack(alignment: .leading, spacing: Spacing.m) {
            Text("Modifications · \(changes.count + omitted)").font(Typography.sectionTitle)
            if changes.isEmpty {
                Label("Aucune modification locale", systemImage: "checkmark.circle").foregroundStyle(Palette.textSecondary).font(Typography.body)
            }
            ForEach(changes) { change in
                GitChangeRow(change: change, root: root)
            }
            if omitted > 0 {
                InspectorNotice(title: "Liste tronquée", message: "\(omitted) autres modifications non affichées sur cet appareil", symbol: "ellipsis.circle")
            }
        }
    }
}
