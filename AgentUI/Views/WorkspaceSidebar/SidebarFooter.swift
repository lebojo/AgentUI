import SwiftUI
import AppKit

struct SidebarFooter: View {
    let store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Spacing.s) {
                Image(systemName: "terminal")
                Text(store.isImporting ? "Importing repositories…" : "\(store.terminalCount) terminals")
                Spacer()
                if store.isImporting { ProgressView().controlSize(.mini) }
                else { Text("\(store.sessions.runningCount) open") }
            }
            .font(Typography.s).foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.l).padding(.vertical, Spacing.l)
        }
    }
}
