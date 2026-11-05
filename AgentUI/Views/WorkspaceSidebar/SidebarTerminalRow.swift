import SwiftUI

struct SidebarTerminalRow: View {
    @Environment(WorkspaceStore.self) private var store

    let terminal: TerminalRecord

    var body: some View {
        SidebarSubagentDisclosure(expansionID: terminal.id, terminalIDs: [terminal.id]) {
            SidebarTerminalLabel(name: terminal.name, session: store.sessions.session(terminal.id))
                .padding(.vertical, Spacing.xxs)
                .tag(terminal.id)
                .terminalDragSource(terminal.id)
                .contextMenu { SidebarTerminalMenu(terminal: terminal) }
                .swipeActions(edge: .trailing) {
                    RemovalButton(removal: .terminal(terminal.id), placement: .swipe)
                }
        }
    }
}
