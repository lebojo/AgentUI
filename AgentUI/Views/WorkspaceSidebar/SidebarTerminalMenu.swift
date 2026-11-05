import SwiftUI

struct SidebarTerminalMenu: View {
    @Environment(WorkspaceStore.self) private var store
    @Environment(WorkspacePresentation.self) private var presentation

    let terminal: TerminalRecord

    var body: some View {
        Button("Rename…", systemImage: "pencil") { presentation.sheet = .rename(terminal.id, terminal.name) }
        if terminal.hasCustomName {
            Button("Use Conversation Name", systemImage: "bubble.left") { store.useAutomaticName(terminal.id) }
        }
        Divider()
        RemovalButton(removal: .terminal(terminal.id), placement: .menu)
    }
}
