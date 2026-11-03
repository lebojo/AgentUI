import SwiftUI

struct SidebarSingleTerminalLabel: View {
    @Environment(WorkspaceStore.self) private var store

    let terminal: TerminalRecord

    var body: some View {
        SidebarTerminalLabel(name: terminal.name, session: store.sessions.session(terminal.id))
            .padding(.vertical, Spacing.xxs)
            .terminalDragSource(terminal.id)
    }
}
