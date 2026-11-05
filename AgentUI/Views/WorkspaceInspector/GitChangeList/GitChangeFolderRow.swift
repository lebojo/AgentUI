import SwiftUI

struct GitChangeFolderRow: View {
    @Binding var isCollapsed: Bool

    let name: String
    let path: String

    var body: some View {
        Button { isCollapsed.toggle() } label: {
            HStack(spacing: Spacing.xs) {
                Image(systemName: isCollapsed ? "chevron.forward" : "chevron.down")
                    .font(Typography.xs).foregroundStyle(Palette.textSecondary)
                    .frame(width: IconSize.xs)
                Label(name, systemImage: "folder").lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).font(Typography.body).help(path)
    }
}
