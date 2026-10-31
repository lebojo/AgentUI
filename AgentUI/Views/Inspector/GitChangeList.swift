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

private struct GitChangeRow: View {
    @Environment(InspectorPreviews.self) private var previews

    let change: GitChange
    let root: String

    var body: some View {
        Button {
            previews.diff(change, at: root)
        } label: {
            HStack(alignment: .top, spacing: Spacing.m) {
                Text(change.status).font(Typography.captionMono).foregroundStyle(Palette.textSecondary).frame(width: Dimension.Inspector.statusColumnWidth)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(change.path).font(Typography.body).lineLimit(2).truncationMode(.middle)
                    Text(change.description).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, Spacing.xxs).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Afficher le diff de \(change.path)")
    }
}
