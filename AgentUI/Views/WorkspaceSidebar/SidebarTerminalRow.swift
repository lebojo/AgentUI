import SwiftUI

struct SidebarTerminalRow: View {
    @Environment(WorkspaceStore.self) private var store

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    let terminal: TerminalRecord
    let worktreePath: String

    var body: some View {
        SidebarSubagentDisclosure(expansionID: terminal.id, terminalIDs: [terminal.id]) {
            SidebarTerminalLabel(name: terminal.name, session: store.sessions.session(terminal.id),
                                 divergentBranch: store.sessions.divergentBranch(for: terminal.id, worktreePath: worktreePath))
                .padding(.vertical, Spacing.xxs)
                .tag(terminal.id)
                .terminalDragSource(terminal.id)
                .contextMenu { SidebarTerminalMenu(sheet: $sheet, removal: $removal, terminal: terminal) }
                .swipeActions(edge: .trailing) {
                    RemovalButton(pending: $removal, removal: .terminal(terminal.id), placement: .swipe)
                }
        }
    }
}
