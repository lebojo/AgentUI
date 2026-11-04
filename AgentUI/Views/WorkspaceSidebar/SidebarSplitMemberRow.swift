import SwiftUI

struct SidebarSplitMemberRow: View {
    @Environment(WorkspaceStore.self) private var store

    @Binding var sheet: WorkspaceSheet?
    @Binding var removal: Removal?

    let terminal: TerminalRecord
    let worktreePath: String
    let isFocused: Bool

    var body: some View {
        Button { store.selection = terminal.id } label: {
            SidebarTerminalLabel(name: terminal.name, session: store.sessions.session(terminal.id),
                                 divergentBranch: store.sessions.divergentBranch(for: terminal.id, worktreePath: worktreePath))
            .fontWeight(isFocused ? .semibold : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isFocused ? .isSelected : [])
        .terminalDragSource(terminal.id)
        .contextMenu { SidebarTerminalMenu(sheet: $sheet, removal: $removal, terminal: terminal) }
    }
}
