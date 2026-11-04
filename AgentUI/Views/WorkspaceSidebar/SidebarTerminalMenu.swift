import SwiftUI

struct SidebarTerminalMenu: View {
    @Environment(WorkspaceStore.self) private var store

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    let terminal: TerminalRecord

    var body: some View {
        Button("Rename…", systemImage: "pencil") { sheet = .rename(terminal.id, terminal.name) }
        if terminal.hasCustomName {
            Button("Use Conversation Name", systemImage: "bubble.left") { store.useAutomaticName(terminal.id) }
        }
        Divider()
        RemovalButton(pending: $removal, removal: .terminal(terminal.id), placement: .menu)
    }
}
