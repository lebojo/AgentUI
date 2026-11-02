import SwiftUI

struct MobileHostRow: View {
    @Environment(MobileWorkspaceStore.self) private var store

    let host: SavedHost

    var body: some View {
        HStack {
            Label {
                VStack(alignment: .leading) {
                    Text(host.name).foregroundStyle(Palette.textPrimary)
                    Text(host.summary).font(Typography.caption).foregroundStyle(Palette.textSecondary)
                }
            } icon: { Image(systemName: "desktopcomputer") }
            Spacer()
            if store.selectedHostID == host.id {
                Image(systemName: "checkmark").foregroundStyle(Palette.accent).accessibilityLabel("Selected")
            }
        }
    }
}
