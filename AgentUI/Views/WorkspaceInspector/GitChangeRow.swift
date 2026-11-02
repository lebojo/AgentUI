import SwiftUI

struct GitChangeRow: View {
    @Environment(InspectorPreviews.self) private var previews

    let change: GitChange
    let root: String
    let scope: GitChangeScope

    var body: some View {
        Button {
            previews.diff(change, in: scope, at: root)
        } label: {
            HStack(alignment: .top, spacing: Spacing.m) {
                Text(change.status).font(Typography.captionMono).foregroundStyle(Palette.textSecondary).frame(width: Dimension.Inspector.statusColumnWidth)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(change.path).font(Typography.body).lineLimit(2).truncationMode(.middle)
                    Text(change.description).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }.padding(.vertical, Spacing.xxs).contentShape(Rectangle())
        }.buttonStyle(.plain).help("Show diff for \(change.path)")
    }
}
