import SwiftUI

struct SidebarFooter: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.s) {
                Image(systemName: "terminal")
                Text(store.isImporting ? "Importing repositories…" : "\(store.terminalCount) terminals")
                Spacer()
                if store.isImporting { ProgressView().controlSize(.mini) }
                else { Text("\(store.sessions.runningWorkspaceCount) open") }
            }
            .font(Typography.s).foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.l)
        }
    }
}
